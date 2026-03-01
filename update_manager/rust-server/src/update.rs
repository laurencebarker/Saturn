use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::{IntoResponse, Json, Response},
};
use chrono::Local;
use serde::{Deserialize, Serialize};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::process::Command;
use tracing::error;

use crate::state::{
    AppState, DEFAULT_STAGE_WORKTREE_KEEP, DEFAULT_UPDATE_HEALTH_TIMEOUT_SECS,
    DEFAULT_UPDATE_KEEP_SNAPSHOTS,
};
use crate::util::{
    current_repo_root, is_safe_ref_name, is_safe_repo_part, json_error,
    list_repo_root_candidates, output_error_text, validate_saturn_repo_root,
};

// --- Types ---

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdatePolicy {
    pub owner: String,
    pub repo: String,
    #[serde(default)]
    pub repo_url_configured: bool,
    pub remote: String,
    pub channel: String,
    pub stable_ref: String,
    pub beta_ref: String,
    pub custom_ref: Option<String>,
    pub auto_snapshot: bool,
    pub keep_snapshots: usize,
    pub healthcheck_url: String,
    pub healthcheck_timeout_secs: u64,
}

impl Default for UpdatePolicy {
    fn default() -> Self {
        Self {
            owner: String::new(),
            repo: String::new(),
            repo_url_configured: false,
            remote: "origin".to_string(),
            channel: "stable".to_string(),
            stable_ref: "main".to_string(),
            beta_ref: "beta".to_string(),
            custom_ref: None,
            auto_snapshot: true,
            keep_snapshots: DEFAULT_UPDATE_KEEP_SNAPSHOTS,
            healthcheck_url: "http://127.0.0.1:8080/healthz".to_string(),
            healthcheck_timeout_secs: DEFAULT_UPDATE_HEALTH_TIMEOUT_SECS,
        }
    }
}

#[derive(Debug, Deserialize, Default)]
pub struct UpdateStartReq {
    channel: Option<String>,
    custom_ref: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LastUpdateState {
    timestamp: String,
    previous_repo_root: String,
    current_repo_root: String,
    previous_commit: String,
    current_commit: String,
    snapshot_path: Option<String>,
    channel: String,
    target_ref: String,
    source_remote: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct ApplianceUpdateJob {
    id: String,
    status: String,
    message: String,
    started_at: String,
    finished_at: Option<String>,
    channel: String,
    target_ref: String,
    source_remote: String,
    previous_commit: Option<String>,
    target_commit: Option<String>,
    previous_repo_root: Option<String>,
    new_repo_root: Option<String>,
    snapshot_path: Option<String>,
    rolled_back: bool,
    log: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct UpdateActivity {
    pub id: String,
    pub kind: String,
    pub started_at: String,
    pub detail: String,
}

pub struct UpdateActivityGuard {
    id: String,
}

impl Drop for UpdateActivityGuard {
    fn drop(&mut self) {
        release_update_activity(&self.id);
    }
}

#[derive(Deserialize)]
pub struct SetRepoRootReq {
    repo_root: String,
}

// --- Statics ---

static APPLIANCE_UPDATE_JOB: OnceLock<Mutex<Option<ApplianceUpdateJob>>> = OnceLock::new();
static UPDATE_ACTIVITY: OnceLock<Mutex<Option<UpdateActivity>>> = OnceLock::new();

fn appliance_update_slot() -> &'static Mutex<Option<ApplianceUpdateJob>> {
    APPLIANCE_UPDATE_JOB.get_or_init(|| Mutex::new(None))
}

fn update_activity_slot() -> &'static Mutex<Option<UpdateActivity>> {
    UPDATE_ACTIVITY.get_or_init(|| Mutex::new(None))
}

// --- Job management ---

fn get_appliance_update_job() -> Option<ApplianceUpdateJob> {
    appliance_update_slot().lock().unwrap().clone()
}

fn set_appliance_update_job(job: ApplianceUpdateJob) {
    let mut guard = appliance_update_slot().lock().unwrap();
    *guard = Some(job);
}

fn update_appliance_update_job(id: &str, f: impl FnOnce(&mut ApplianceUpdateJob)) {
    let mut guard = appliance_update_slot().lock().unwrap();
    if let Some(job) = guard.as_mut() {
        if job.id == id {
            f(job);
        }
    }
}

fn append_appliance_update_log(id: &str, line: impl Into<String>) {
    let line = line.into();
    update_appliance_update_job(id, |job| {
        job.log.push(line);
        if job.log.len() > 400 {
            let excess = job.log.len() - 400;
            job.log.drain(0..excess);
        }
    });
}

fn finish_appliance_update_job(id: &str, status: &str, message: impl Into<String>) {
    let msg = message.into();
    update_appliance_update_job(id, |job| {
        job.status = status.to_string();
        job.message = msg;
        job.finished_at = Some(Local::now().to_rfc3339());
    });
}

// --- Activity guard ---

pub fn begin_update_activity(
    kind: &str,
    detail: impl Into<String>,
) -> Result<UpdateActivityGuard, String> {
    let mut guard = update_activity_slot().lock().unwrap();
    if let Some(active) = guard.as_ref() {
        let suffix = if active.detail.is_empty() {
            String::new()
        } else {
            format!(" ({})", active.detail)
        };
        return Err(format!(
            "{} already running since {}{}",
            active.kind, active.started_at, suffix
        ));
    }
    let id = format!(
        "activity-{}-{}",
        std::process::id(),
        Local::now().format("%Y%m%d%H%M%S%3f")
    );
    *guard = Some(UpdateActivity {
        id: id.clone(),
        kind: kind.to_string(),
        started_at: Local::now().to_rfc3339(),
        detail: detail.into(),
    });
    Ok(UpdateActivityGuard { id })
}

fn release_update_activity(id: &str) {
    let mut guard = update_activity_slot().lock().unwrap();
    if guard.as_ref().map(|a| a.id.as_str()) == Some(id) {
        *guard = None;
    }
}

// --- Policy helpers ---

pub fn expected_remote_url(policy: &UpdatePolicy) -> String {
    format!(
        "https://github.com/{}/{}.git",
        policy.owner.trim(),
        policy.repo.trim()
    )
}

pub fn update_policy_repo_configured(policy: &UpdatePolicy) -> bool {
    policy.repo_url_configured
        && is_safe_repo_part(policy.owner.trim())
        && is_safe_repo_part(policy.repo.trim())
}

pub fn normalize_update_policy(mut policy: UpdatePolicy, state: &AppState) -> UpdatePolicy {
    let owner = policy.owner.trim();
    let repo = policy.repo.trim();
    let repo_valid = is_safe_repo_part(owner) && is_safe_repo_part(repo);
    let legacy_default_unconfigured = !policy.repo_url_configured
        && owner.eq_ignore_ascii_case("Saturn")
        && repo.eq_ignore_ascii_case("Saturn");
    if repo_valid && !legacy_default_unconfigured {
        policy.owner = owner.to_string();
        policy.repo = repo.to_string();
        policy.repo_url_configured = true;
    } else {
        policy.owner.clear();
        policy.repo.clear();
        policy.repo_url_configured = false;
    }

    let remote = policy.remote.trim();
    if remote.is_empty()
        || !remote
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-' || c == '.')
    {
        policy.remote = "origin".to_string();
    } else {
        policy.remote = remote.to_string();
    }

    let channel = policy.channel.trim().to_ascii_lowercase();
    policy.channel = match channel.as_str() {
        "stable" | "beta" | "custom" => channel,
        _ => "stable".to_string(),
    };

    if !is_safe_ref_name(policy.stable_ref.trim()) {
        policy.stable_ref = "main".to_string();
    } else {
        policy.stable_ref = policy.stable_ref.trim().to_string();
    }
    if !is_safe_ref_name(policy.beta_ref.trim()) {
        policy.beta_ref = "beta".to_string();
    } else {
        policy.beta_ref = policy.beta_ref.trim().to_string();
    }

    policy.custom_ref = policy
        .custom_ref
        .as_deref()
        .map(str::trim)
        .filter(|v| is_safe_ref_name(v))
        .map(ToOwned::to_owned);

    policy.keep_snapshots = policy.keep_snapshots.clamp(1, 50);
    policy.healthcheck_timeout_secs = policy.healthcheck_timeout_secs.clamp(2, 30);

    let hc = policy.healthcheck_url.trim();
    if hc.is_empty() {
        policy.healthcheck_url = format!("http://{}/healthz", state.saturn_addr);
    } else {
        policy.healthcheck_url = hc.to_string();
    }
    policy
}

pub async fn load_update_policy(state: &AppState) -> Result<UpdatePolicy, String> {
    let policy = match tokio::fs::read_to_string(&state.update_policy_file).await {
        Ok(data) => serde_json::from_str::<UpdatePolicy>(&data).unwrap_or_default(),
        Err(_) => UpdatePolicy::default(),
    };
    let normalized = normalize_update_policy(policy, state);
    if let Err(e) = save_update_policy(state, normalized.clone()).await {
        error!("failed to persist update policy: {e}");
    }
    Ok(normalized)
}

pub async fn save_update_policy(
    state: &AppState,
    policy: UpdatePolicy,
) -> Result<UpdatePolicy, String> {
    let normalized = normalize_update_policy(policy, state);
    if let Some(parent) = state.update_policy_file.parent() {
        tokio::fs::create_dir_all(parent)
            .await
            .map_err(|e| e.to_string())?;
    }
    let bytes = serde_json::to_vec_pretty(&normalized).map_err(|e| e.to_string())?;
    tokio::fs::write(&state.update_policy_file, bytes)
        .await
        .map_err(|e| e.to_string())?;
    let _ = tokio::fs::set_permissions(
        &state.update_policy_file,
        std::fs::Permissions::from_mode(0o640),
    )
    .await;
    Ok(normalized)
}

async fn read_last_update_state(state: &AppState) -> Option<LastUpdateState> {
    let data = tokio::fs::read_to_string(&state.update_state_file)
        .await
        .ok()?;
    serde_json::from_str::<LastUpdateState>(&data).ok()
}

async fn write_last_update_state(state: &AppState, last: &LastUpdateState) -> Result<(), String> {
    if let Some(parent) = state.update_state_file.parent() {
        tokio::fs::create_dir_all(parent)
            .await
            .map_err(|e| e.to_string())?;
    }
    let bytes = serde_json::to_vec_pretty(last).map_err(|e| e.to_string())?;
    tokio::fs::write(&state.update_state_file, bytes)
        .await
        .map_err(|e| e.to_string())?;
    let _ = tokio::fs::set_permissions(
        &state.update_state_file,
        std::fs::Permissions::from_mode(0o640),
    )
    .await;
    Ok(())
}

fn select_channel_and_target(
    policy: &UpdatePolicy,
    req: &UpdateStartReq,
) -> Result<(String, String), String> {
    let channel = req
        .channel
        .as_deref()
        .map(|c| c.trim().to_ascii_lowercase())
        .filter(|c| !c.is_empty())
        .unwrap_or_else(|| policy.channel.clone());
    let channel = match channel.as_str() {
        "stable" | "beta" | "custom" => channel,
        _ => return Err("channel must be stable, beta, or custom".to_string()),
    };
    let target = match channel.as_str() {
        "stable" => policy.stable_ref.clone(),
        "beta" => policy.beta_ref.clone(),
        "custom" => req
            .custom_ref
            .as_deref()
            .map(str::trim)
            .filter(|v| !v.is_empty())
            .map(ToOwned::to_owned)
            .or_else(|| policy.custom_ref.clone())
            .ok_or_else(|| "custom channel requires custom_ref".to_string())?,
        _ => unreachable!(),
    };
    if !is_safe_ref_name(target.trim()) {
        return Err("invalid target ref".to_string());
    }
    Ok((channel, target.trim().to_string()))
}

pub async fn set_active_repo_root(state: &AppState, new_root: &Path) -> Result<(), String> {
    validate_saturn_repo_root(new_root)?;
    if let Some(parent) = state.repo_root_file.parent() {
        tokio::fs::create_dir_all(parent)
            .await
            .map_err(|e| format!("failed to create repo_root directory: {e}"))?;
    }
    tokio::fs::write(&state.repo_root_file, format!("{}\n", new_root.display()))
        .await
        .map_err(|e| format!("failed to persist repo_root: {e}"))?;
    let _ = tokio::fs::set_permissions(
        &state.repo_root_file,
        std::fs::Permissions::from_mode(0o640),
    )
    .await;
    {
        let mut guard = state.repo_root.write().unwrap_or_else(|e| e.into_inner());
        *guard = new_root.to_path_buf();
    }
    Ok(())
}

// --- Git helpers ---

async fn git_rev_parse(repo_root: &Path, rev: &str) -> Result<String, String> {
    let output = Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .arg("rev-parse")
        .arg(rev)
        .output()
        .await
        .map_err(|e| e.to_string())?;
    if !output.status.success() {
        return Err(format!(
            "git rev-parse {rev} failed: {}",
            output_error_text(&output)
        ));
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

async fn create_repo_snapshot(repo_root: &Path, snapshot_dir: &Path) -> Result<PathBuf, String> {
    let parent = repo_root
        .parent()
        .ok_or_else(|| "repo_root has no parent".to_string())?;
    let base = repo_root
        .file_name()
        .and_then(|s| s.to_str())
        .ok_or_else(|| "repo_root basename invalid".to_string())?;
    tokio::fs::create_dir_all(snapshot_dir)
        .await
        .map_err(|e| e.to_string())?;
    let ts = Local::now().format("%Y%m%d-%H%M%S");
    let out_path = snapshot_dir.join(format!("{base}-snapshot-{ts}.tar.gz"));
    let output = Command::new("tar")
        .arg("-C")
        .arg(parent)
        .arg("-czf")
        .arg(&out_path)
        .arg(base)
        .output()
        .await
        .map_err(|e| e.to_string())?;
    if !output.status.success() {
        return Err(format!(
            "snapshot tar failed: {}",
            output_error_text(&output)
        ));
    }
    Ok(out_path)
}

async fn prune_snapshots(snapshot_dir: &Path, keep: usize) -> Result<(), String> {
    let mut entries = tokio::fs::read_dir(snapshot_dir)
        .await
        .map_err(|e| e.to_string())?;
    let mut files: Vec<(SystemTime, PathBuf)> = Vec::new();
    while let Some(ent) = entries.next_entry().await.map_err(|e| e.to_string())? {
        let ft = ent.file_type().await.map_err(|e| e.to_string())?;
        if !ft.is_file() {
            continue;
        }
        let modified = ent
            .metadata()
            .await
            .ok()
            .and_then(|m| m.modified().ok())
            .unwrap_or(UNIX_EPOCH);
        files.push((modified, ent.path()));
    }
    files.sort_by(|a, b| b.0.cmp(&a.0));
    for (_modified, path) in files.into_iter().skip(keep) {
        let _ = tokio::fs::remove_file(path).await;
    }
    Ok(())
}

async fn remove_worktree(repo_root: &Path, worktree: &Path) -> Result<(), String> {
    if !worktree.exists() {
        return Ok(());
    }

    let out = Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .arg("worktree")
        .arg("remove")
        .arg("--force")
        .arg(worktree)
        .output()
        .await;

    match out {
        Ok(output) if output.status.success() => Ok(()),
        Ok(output) => {
            tokio::fs::remove_dir_all(worktree).await.map_err(|e| {
                format!(
                    "worktree remove failed ({}) and cleanup failed: {}",
                    output_error_text(&output),
                    e
                )
            })?;
            Ok(())
        }
        Err(e) => {
            tokio::fs::remove_dir_all(worktree)
                .await
                .map_err(|cleanup_err| {
                    format!(
                        "worktree remove command failed ({e}) and cleanup failed: {cleanup_err}"
                    )
                })?;
            Ok(())
        }
    }
}

async fn prune_staged_worktrees(
    repo_root: &Path,
    staging_dir: &Path,
    keep: usize,
    protected: &[PathBuf],
) -> Result<(), String> {
    let mut entries = match tokio::fs::read_dir(staging_dir).await {
        Ok(v) => v,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(e) => return Err(e.to_string()),
    };

    let mut dirs: Vec<(SystemTime, PathBuf)> = Vec::new();
    while let Some(ent) = entries.next_entry().await.map_err(|e| e.to_string())? {
        let ft = ent.file_type().await.map_err(|e| e.to_string())?;
        if !ft.is_dir() {
            continue;
        }
        let modified = ent
            .metadata()
            .await
            .ok()
            .and_then(|m| m.modified().ok())
            .unwrap_or(UNIX_EPOCH);
        dirs.push((modified, ent.path()));
    }

    dirs.sort_by(|a, b| b.0.cmp(&a.0));
    let mut kept = 0usize;
    for (_modified, path) in dirs {
        if protected.iter().any(|p| p == &path) {
            continue;
        }
        if kept < keep {
            kept += 1;
            continue;
        }
        let _ = remove_worktree(repo_root, &path).await;
    }

    let _ = Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .arg("worktree")
        .arg("prune")
        .output()
        .await;
    Ok(())
}

async fn health_check_url(url: &str, timeout_secs: u64) -> Result<(), String> {
    let output = Command::new("curl")
        .arg("-fsS")
        .arg("--max-time")
        .arg(timeout_secs.to_string())
        .arg(url)
        .output()
        .await
        .map_err(|e| e.to_string())?;
    if output.status.success() {
        Ok(())
    } else {
        Err(format!(
            "health check failed: {}",
            output_error_text(&output)
        ))
    }
}

// --- Appliance update flow ---

async fn run_appliance_update(
    state: AppState,
    job_id: String,
    policy: UpdatePolicy,
    channel: String,
    target_ref: String,
) {
    let active_root = current_repo_root(&state);
    update_appliance_update_job(&job_id, |job| {
        job.previous_repo_root = Some(active_root.display().to_string());
    });

    if let Err(e) = validate_saturn_repo_root(&active_root) {
        finish_appliance_update_job(&job_id, "error", e);
        return;
    }

    let expected_remote = expected_remote_url(&policy);
    append_appliance_update_log(
        &job_id,
        format!(
            "Enforcing git remote {} -> {}",
            policy.remote, expected_remote
        ),
    );
    let set_remote = Command::new("git")
        .arg("-C")
        .arg(&active_root)
        .arg("remote")
        .arg("set-url")
        .arg(&policy.remote)
        .arg(&expected_remote)
        .output()
        .await;
    match set_remote {
        Ok(out) if out.status.success() => {}
        Ok(out) => {
            finish_appliance_update_job(
                &job_id,
                "error",
                format!("failed to set remote: {}", output_error_text(&out)),
            );
            return;
        }
        Err(e) => {
            finish_appliance_update_job(&job_id, "error", format!("failed to set remote: {e}"));
            return;
        }
    }

    append_appliance_update_log(
        &job_id,
        format!("Fetching from {} ({})", policy.remote, expected_remote),
    );
    let fetch_out = Command::new("git")
        .arg("-C")
        .arg(&active_root)
        .arg("fetch")
        .arg("--prune")
        .arg(&policy.remote)
        .output()
        .await;
    match fetch_out {
        Ok(out) if out.status.success() => {}
        Ok(out) => {
            finish_appliance_update_job(
                &job_id,
                "error",
                format!("git fetch failed: {}", output_error_text(&out)),
            );
            return;
        }
        Err(e) => {
            finish_appliance_update_job(&job_id, "error", format!("git fetch failed: {e}"));
            return;
        }
    }

    let previous_commit = match git_rev_parse(&active_root, "HEAD").await {
        Ok(v) => v,
        Err(e) => {
            finish_appliance_update_job(&job_id, "error", e);
            return;
        }
    };
    update_appliance_update_job(&job_id, |job| {
        job.previous_commit = Some(previous_commit.clone());
    });

    let resolve_ref = if channel == "custom" {
        target_ref.clone()
    } else {
        format!("{}/{}", policy.remote, target_ref)
    };
    let target_commit = match git_rev_parse(&active_root, &resolve_ref).await {
        Ok(v) => v,
        Err(e) => {
            finish_appliance_update_job(&job_id, "error", e);
            return;
        }
    };
    update_appliance_update_job(&job_id, |job| {
        job.target_commit = Some(target_commit.clone());
    });

    if previous_commit == target_commit {
        finish_appliance_update_job(
            &job_id,
            "no_change",
            format!("already on {target_commit} ({resolve_ref})"),
        );
        return;
    }

    let snapshot_path = if policy.auto_snapshot {
        append_appliance_update_log(&job_id, "Creating pre-update snapshot");
        match create_repo_snapshot(&active_root, &state.snapshot_dir).await {
            Ok(path) => {
                let _ = prune_snapshots(&state.snapshot_dir, policy.keep_snapshots).await;
                update_appliance_update_job(&job_id, |job| {
                    job.snapshot_path = Some(path.display().to_string());
                });
                Some(path)
            }
            Err(e) => {
                finish_appliance_update_job(&job_id, "error", format!("snapshot failed: {e}"));
                return;
            }
        }
    } else {
        None
    };

    if let Err(e) = tokio::fs::create_dir_all(&state.staging_dir).await {
        finish_appliance_update_job(
            &job_id,
            "error",
            format!("failed to create staging dir: {e}"),
        );
        return;
    }
    let repo_name = active_root
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("repo");
    let ts = Local::now().format("%Y%m%d-%H%M%S");
    let short_commit = target_commit.chars().take(8).collect::<String>();
    let stage_dir = state
        .staging_dir
        .join(format!("{repo_name}-{ts}-{short_commit}"));

    append_appliance_update_log(
        &job_id,
        format!("Creating staged worktree at {}", stage_dir.display()),
    );
    let stage_out = Command::new("git")
        .arg("-C")
        .arg(&active_root)
        .arg("worktree")
        .arg("add")
        .arg("--detach")
        .arg(&stage_dir)
        .arg(&target_commit)
        .output()
        .await;
    match stage_out {
        Ok(out) if out.status.success() => {}
        Ok(out) => {
            finish_appliance_update_job(
                &job_id,
                "error",
                format!("git worktree add failed: {}", output_error_text(&out)),
            );
            return;
        }
        Err(e) => {
            finish_appliance_update_job(
                &job_id,
                "error",
                format!("git worktree add failed: {e}"),
            );
            return;
        }
    }

    if let Err(e) = set_active_repo_root(&state, &stage_dir).await {
        let _ = remove_worktree(&active_root, &stage_dir).await;
        finish_appliance_update_job(&job_id, "error", e);
        return;
    }
    update_appliance_update_job(&job_id, |job| {
        job.new_repo_root = Some(stage_dir.display().to_string());
    });

    if let Err(e) =
        health_check_url(&policy.healthcheck_url, policy.healthcheck_timeout_secs).await
    {
        let _ = set_active_repo_root(&state, &active_root).await;
        let _ = remove_worktree(&active_root, &stage_dir).await;
        update_appliance_update_job(&job_id, |job| {
            job.rolled_back = true;
            job.new_repo_root = Some(active_root.display().to_string());
        });
        finish_appliance_update_job(
            &job_id,
            "error",
            format!("{e}; reverted to previous repo root"),
        );
        return;
    }

    let last = LastUpdateState {
        timestamp: Local::now().to_rfc3339(),
        previous_repo_root: active_root.display().to_string(),
        current_repo_root: stage_dir.display().to_string(),
        previous_commit: previous_commit.clone(),
        current_commit: target_commit.clone(),
        snapshot_path: snapshot_path.as_ref().map(|p| p.display().to_string()),
        channel: channel.clone(),
        target_ref: target_ref.clone(),
        source_remote: expected_remote.clone(),
    };
    if let Err(e) = write_last_update_state(&state, &last).await {
        append_appliance_update_log(
            &job_id,
            format!("warning: failed to persist update state: {e}"),
        );
    }
    let protected = vec![stage_dir.clone(), active_root.clone()];
    if let Err(e) = prune_staged_worktrees(
        &stage_dir,
        &state.staging_dir,
        DEFAULT_STAGE_WORKTREE_KEEP,
        &protected,
    )
    .await
    {
        append_appliance_update_log(
            &job_id,
            format!("warning: failed to prune staged worktrees: {e}"),
        );
    }

    finish_appliance_update_job(
        &job_id,
        "done",
        format!(
            "updated {} -> {} and switched repo root to {}",
            previous_commit,
            target_commit,
            stage_dir.display()
        ),
    );
}

// --- Handlers ---

pub async fn get_update_policy(State(state): State<AppState>) -> Response {
    match load_update_policy(&state).await {
        Ok(policy) => Json(serde_json::json!({ "policy": policy })).into_response(),
        Err(e) => json_error(StatusCode::INTERNAL_SERVER_ERROR, &e),
    }
}

pub async fn set_update_policy(
    State(state): State<AppState>,
    Json(policy): Json<UpdatePolicy>,
) -> Response {
    match save_update_policy(&state, policy).await {
        Ok(policy) => {
            Json(serde_json::json!({ "status": "ok", "policy": policy })).into_response()
        }
        Err(e) => json_error(StatusCode::INTERNAL_SERVER_ERROR, &e),
    }
}

pub async fn update_start(
    State(state): State<AppState>,
    Json(req): Json<UpdateStartReq>,
) -> Response {
    if let Some(job) = get_appliance_update_job() {
        if job.status == "running" {
            return (
                StatusCode::CONFLICT,
                Json(serde_json::json!({
                    "message": "update already running",
                    "job_id": job.id,
                })),
            )
                .into_response();
        }
    }

    let policy = match load_update_policy(&state).await {
        Ok(p) => p,
        Err(e) => return json_error(StatusCode::INTERNAL_SERVER_ERROR, &e),
    };
    if !update_policy_repo_configured(&policy) {
        return json_error(
            StatusCode::BAD_REQUEST,
            "Appliance Update repo URL is not configured. Save a GitHub repo URL first.",
        );
    }
    let (channel, target_ref) = match select_channel_and_target(&policy, &req) {
        Ok(v) => v,
        Err(e) => return json_error(StatusCode::BAD_REQUEST, &e),
    };
    let activity_guard = match begin_update_activity(
        "appliance-update",
        format!("channel={channel} target_ref={target_ref}"),
    ) {
        Ok(g) => g,
        Err(e) => return json_error(StatusCode::CONFLICT, &e),
    };
    let job_id = format!(
        "upd-{}-{}",
        std::process::id(),
        Local::now().format("%Y%m%d%H%M%S")
    );
    set_appliance_update_job(ApplianceUpdateJob {
        id: job_id.clone(),
        status: "running".to_string(),
        message: "starting update".to_string(),
        started_at: Local::now().to_rfc3339(),
        finished_at: None,
        channel: channel.clone(),
        target_ref: target_ref.clone(),
        source_remote: expected_remote_url(&policy),
        previous_commit: None,
        target_commit: None,
        previous_repo_root: None,
        new_repo_root: None,
        snapshot_path: None,
        rolled_back: false,
        log: vec![
            format!("channel={channel}"),
            format!("target_ref={target_ref}"),
            format!("source={}", expected_remote_url(&policy)),
        ],
    });

    let state_clone = state.clone();
    let job_id_clone = job_id.clone();
    tokio::spawn(async move {
        let _activity_guard = activity_guard;
        run_appliance_update(state_clone, job_id_clone, policy, channel, target_ref).await;
    });

    Json(serde_json::json!({
        "status": "started",
        "job_id": job_id,
    }))
    .into_response()
}

pub async fn update_status(State(state): State<AppState>) -> Response {
    let job = get_appliance_update_job();
    let last = read_last_update_state(&state).await;
    Json(serde_json::json!({
        "job": job,
        "last_update": last
    }))
    .into_response()
}

pub async fn update_rollback(State(state): State<AppState>) -> Response {
    if let Some(job) = get_appliance_update_job() {
        if job.status == "running" {
            return json_error(StatusCode::CONFLICT, "update in progress");
        }
    }
    let _activity_guard = match begin_update_activity("appliance-rollback", "manual rollback") {
        Ok(g) => g,
        Err(e) => return json_error(StatusCode::CONFLICT, &e),
    };

    let last = match read_last_update_state(&state).await {
        Some(v) => v,
        None => {
            return json_error(
                StatusCode::NOT_FOUND,
                "no update state available for rollback",
            )
        }
    };
    let current_root = current_repo_root(&state);
    let rollback_root = PathBuf::from(last.previous_repo_root.clone());
    if !rollback_root.is_dir() {
        return json_error(StatusCode::BAD_REQUEST, "rollback repo root is missing");
    }
    if current_root == rollback_root {
        return Json(serde_json::json!({
            "status": "ok",
            "message": "already on rollback target",
            "repo_root": rollback_root,
        }))
        .into_response();
    }

    if let Err(e) = set_active_repo_root(&state, &rollback_root).await {
        return json_error(StatusCode::INTERNAL_SERVER_ERROR, &e);
    }

    let policy = load_update_policy(&state)
        .await
        .unwrap_or_else(|_| normalize_update_policy(UpdatePolicy::default(), &state));
    if let Err(e) =
        health_check_url(&policy.healthcheck_url, policy.healthcheck_timeout_secs).await
    {
        let _ = set_active_repo_root(&state, &current_root).await;
        return json_error(
            StatusCode::INTERNAL_SERVER_ERROR,
            &format!("rollback health check failed: {e}"),
        );
    }

    let rollback_id = format!(
        "rollback-{}-{}",
        std::process::id(),
        Local::now().format("%Y%m%d%H%M%S")
    );
    let previous_commit = git_rev_parse(&current_root, "HEAD")
        .await
        .unwrap_or_else(|_| "unknown".to_string());
    let current_commit = git_rev_parse(&rollback_root, "HEAD")
        .await
        .unwrap_or_else(|_| "unknown".to_string());
    set_appliance_update_job(ApplianceUpdateJob {
        id: rollback_id,
        status: "rolled_back".to_string(),
        message: format!("rolled back repo root to {}", rollback_root.display()),
        started_at: Local::now().to_rfc3339(),
        finished_at: Some(Local::now().to_rfc3339()),
        channel: last.channel.clone(),
        target_ref: last.target_ref.clone(),
        source_remote: last.source_remote.clone(),
        previous_commit: Some(previous_commit.clone()),
        target_commit: Some(current_commit.clone()),
        previous_repo_root: Some(current_root.display().to_string()),
        new_repo_root: Some(rollback_root.display().to_string()),
        snapshot_path: last.snapshot_path.clone(),
        rolled_back: true,
        log: vec![
            format!("rollback from {}", current_root.display()),
            format!("rollback to {}", rollback_root.display()),
        ],
    });

    let updated_last = LastUpdateState {
        timestamp: Local::now().to_rfc3339(),
        previous_repo_root: current_root.display().to_string(),
        current_repo_root: rollback_root.display().to_string(),
        previous_commit,
        current_commit,
        snapshot_path: last.snapshot_path.clone(),
        channel: last.channel,
        target_ref: last.target_ref,
        source_remote: last.source_remote,
    };
    let _ = write_last_update_state(&state, &updated_last).await;

    Json(serde_json::json!({
        "status": "rolled_back",
        "repo_root": rollback_root,
    }))
    .into_response()
}

pub async fn get_repo_root(State(state): State<AppState>) -> impl IntoResponse {
    Json(serde_json::json!({ "repo_root": current_repo_root(&state) }))
}

pub async fn list_repo_roots(State(state): State<AppState>) -> impl IntoResponse {
    let active = current_repo_root(&state);
    let roots = list_repo_root_candidates(&active);
    Json(serde_json::json!({
        "active": active,
        "repo_roots": roots
    }))
}

pub async fn set_repo_root(
    State(state): State<AppState>,
    Json(req): Json<SetRepoRootReq>,
) -> Response {
    let requested = req.repo_root.trim();
    if requested.is_empty() {
        return json_error(StatusCode::BAD_REQUEST, "repo_root is required");
    }

    let canonical = match tokio::fs::canonicalize(requested).await {
        Ok(p) => p,
        Err(e) => {
            return json_error(StatusCode::BAD_REQUEST, &format!("invalid repo_root: {e}"))
        }
    };
    if let Err(e) = validate_saturn_repo_root(&canonical) {
        return json_error(StatusCode::BAD_REQUEST, &e);
    }

    if let Err(e) = set_active_repo_root(&state, &canonical).await {
        return json_error(StatusCode::INTERNAL_SERVER_ERROR, &e);
    }

    Json(serde_json::json!({
        "status": "ok",
        "repo_root": canonical
    }))
    .into_response()
}
