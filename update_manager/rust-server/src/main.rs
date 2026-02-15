use axum::{
    body::Body,
    extract::{DefaultBodyLimit, Multipart, Query, State},
    http::{header, HeaderMap, HeaderValue, Method, Request, StatusCode},
    middleware::{self, Next},
    response::{
        sse::{Event, KeepAlive},
        Html, IntoResponse, Json, Response, Sse,
    },
    routing::{get, post},
    Router,
};
use chrono::Local;
use serde::{Deserialize, Serialize};
use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    sync::{Arc, Mutex, OnceLock, RwLock},
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
use regex::Regex;
use users::get_user_by_uid;
use sysinfo::{Disks, Networks, System};
use tokio::{
    io::{AsyncBufReadExt, AsyncRead, AsyncReadExt, AsyncWriteExt, BufReader},
    process::Command,
    sync::mpsc,
};
use tokio_stream::{wrappers::UnboundedReceiverStream, StreamExt};
use tokio_util::io::ReaderStream;
use tracing::{error, info};

#[derive(Clone)]
struct AppState {
    webroot: PathBuf,
    config_path: PathBuf,
    saturn_addr: String,
    repo_root: Arc<RwLock<PathBuf>>,
    repo_root_file: PathBuf,
    update_policy_file: PathBuf,
    update_state_file: PathBuf,
    snapshot_dir: PathBuf,
    staging_dir: PathBuf,
    restore_max_upload_bytes: u64,
}

const DEFAULT_MAX_BODY_BYTES: u64 = 2 * 1024 * 1024 * 1024;
const DEFAULT_RESTORE_MAX_UPLOAD_BYTES: u64 = 2 * 1024 * 1024 * 1024;
const DEFAULT_UPDATE_HEALTH_TIMEOUT_SECS: u64 = 8;
const DEFAULT_UPDATE_KEEP_SNAPSHOTS: usize = 5;
const DEFAULT_STAGE_WORKTREE_KEEP: usize = 6;
const CSRF_HEADER_NAME: &str = "x-saturn-csrf";
const CSRF_HEADER_VALUE: &str = "1";

#[derive(Debug, Deserialize)]
struct FlagsQuery {
    script: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
struct CfgEntry {
    filename: String,
    name: Option<String>,
    description: Option<String>,
    directory: Option<String>,
    category: Option<String>,
    flags: Option<Vec<String>>,
    version: Option<String>,
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter("info")
        .init();

    let addr = std::env::var("SATURN_ADDR").unwrap_or_else(|_| "127.0.0.1:8080".to_string());
    let webroot = std::env::var("SATURN_WEBROOT").unwrap_or_else(|_| "/var/lib/saturn-web".to_string());
    let config_path = std::env::var("SATURN_CONFIG")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(format!("{webroot}/config.json")));
    let default_repo_root = std::env::var("SATURN_REPO_ROOT").unwrap_or_else(|_| {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/home/pi".to_string());
        format!("{home}/github/Saturn")
    });
    let repo_root_file = std::env::var("SATURN_REPO_ROOT_FILE")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(format!("{webroot}/repo_root.txt")));
    let update_policy_file = std::env::var("SATURN_UPDATE_POLICY_FILE")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(format!("{webroot}/update_policy.json")));
    let update_state_file = std::env::var("SATURN_UPDATE_STATE_FILE")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(format!("{webroot}/update_state.json")));
    let snapshot_dir = std::env::var("SATURN_SNAPSHOT_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(format!("{webroot}/snapshots")));
    let staging_dir = std::env::var("SATURN_STAGING_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(format!("{webroot}/repo-staging")));
    let restore_max_upload_bytes = std::env::var("SATURN_RESTORE_MAX_UPLOAD_BYTES")
        .ok()
        .and_then(|v| v.parse::<u64>().ok())
        .unwrap_or(DEFAULT_RESTORE_MAX_UPLOAD_BYTES);
    let max_body_bytes = std::env::var("SATURN_MAX_BODY_BYTES")
        .ok()
        .and_then(|v| v.parse::<u64>().ok())
        .unwrap_or(DEFAULT_MAX_BODY_BYTES)
        .min(usize::MAX as u64) as usize;

    let mut repo_root = PathBuf::from(default_repo_root);
    if let Ok(saved) = tokio::fs::read_to_string(&repo_root_file).await {
        let saved = saved.trim();
        if !saved.is_empty() {
            let candidate = PathBuf::from(saved);
            if is_saturn_repo_root(&candidate) {
                repo_root = candidate;
            }
        }
    }
    if let Some(parent) = repo_root_file.parent() {
        let _ = tokio::fs::create_dir_all(parent).await;
    }
    if let Some(parent) = update_policy_file.parent() {
        let _ = tokio::fs::create_dir_all(parent).await;
    }
    if let Some(parent) = update_state_file.parent() {
        let _ = tokio::fs::create_dir_all(parent).await;
    }
    let _ = tokio::fs::create_dir_all(&snapshot_dir).await;
    let _ = tokio::fs::create_dir_all(&staging_dir).await;
    let _ = tokio::fs::write(&repo_root_file, format!("{}\n", repo_root.display())).await;

    let state = AppState {
        webroot: PathBuf::from(webroot),
        config_path,
        saturn_addr: addr.clone(),
        repo_root: Arc::new(RwLock::new(repo_root)),
        repo_root_file,
        update_policy_file,
        update_state_file,
        snapshot_dir,
        staging_dir,
        restore_max_upload_bytes,
    };

    let app = Router::new()
        .route("/", get(root_handler))
        .route("/backup", get(backup_handler))
        .route("/backup.html", get(backup_handler))
        .route("/monitor", get(monitor_handler))
        .route("/monitor.html", get(monitor_handler))
        .route("/healthz", get(healthz))
        .route("/get_versions", get(get_versions))
        .route("/get_scripts", get(get_scripts))
        .route("/get_flags", get(get_flags))
        .route("/get_fpga_images", get(get_fpga_images))
        .route("/get_repo_root", get(get_repo_root))
        .route("/list_repo_roots", get(list_repo_roots))
        .route("/set_repo_root", post(set_repo_root))
        .route("/update_policy", get(get_update_policy))
        .route("/update_policy", post(set_update_policy))
        .route("/update_start", post(update_start))
        .route("/update_status", get(update_status))
        .route("/update_rollback", post(update_rollback))
        .route("/backup_full", get(backup_full))
        .route("/restore_full", post(restore_full))
        .route("/pi_image_start", post(pi_image_start))
        .route("/pi_image_status", get(pi_image_status))
        .route("/pi_image_cancel", post(pi_image_cancel))
        .route("/pi_image_download", get(pi_image_download))
        .route("/pi_devices", get(pi_devices))
        .route("/pi_clone_start", post(pi_clone_start))
        .route("/pi_clone_status", get(pi_clone_status))
        .route("/pi_clone_cancel", post(pi_clone_cancel))
        .route("/repair_pack", get(repair_pack))
        .route("/verify_system_config", get(verify_system_config))
        .route("/run", post(run_sse))
        .route("/backup_response", post(no_content))
        .route("/change_password", post(change_password))
        .route("/exit", post(exit_server))
        .route("/get_system_data", get(get_system_data))
        .route("/network_test", get(network_test))
        .route("/kill_process/:pid", post(kill_process))
        .fallback(get(fallback_handler))
        .with_state(state.clone())
        .layer(middleware::from_fn_with_state(
            state.clone(),
            csrf_protect,
        ))
        .layer(DefaultBodyLimit::max(max_body_bytes));

    info!("Saturn server listening on {addr}");
    let listener = tokio::net::TcpListener::bind(&addr).await.expect("bind failed");
    axum::serve(listener, app).await.expect("server failed");
}

async fn root_handler(State(state): State<AppState>) -> impl IntoResponse {
    serve_page(&state.webroot, "index.html").await
}

async fn backup_handler(State(state): State<AppState>) -> impl IntoResponse {
    serve_page(&state.webroot, "backup.html").await
}

async fn monitor_handler(State(state): State<AppState>) -> impl IntoResponse {
    serve_page(&state.webroot, "monitor.html").await
}

async fn healthz() -> impl IntoResponse {
    StatusCode::OK
}

fn route_to_page(path: &str) -> Option<&'static str> {
    match path {
        "/" | "/index" | "/index.html" | "/saturn" | "/saturn/" | "/saturn/index" | "/saturn/index.html" => {
            Some("index.html")
        }
        "/backup" | "/backup/" | "/backup.html" | "/saturn/backup" | "/saturn/backup/" | "/saturn/backup.html" => {
            Some("backup.html")
        }
        "/monitor" | "/monitor/" | "/monitor.html" | "/saturn/monitor" | "/saturn/monitor/" | "/saturn/monitor.html" => {
            Some("monitor.html")
        }
        _ => None,
    }
}

fn stdbuf_binary() -> Option<&'static str> {
    static STDBUF_BIN: OnceLock<Option<&'static str>> = OnceLock::new();
    *STDBUF_BIN.get_or_init(|| {
        if Path::new("/usr/bin/stdbuf").exists() {
            Some("/usr/bin/stdbuf")
        } else if Path::new("/bin/stdbuf").exists() {
            Some("/bin/stdbuf")
        } else {
            None
        }
    })
}

fn build_script_command(script_path: &Path, flags: &[String]) -> Command {
    let is_python = script_path
        .extension()
        .and_then(|ext| ext.to_str())
        .map(|ext| ext.eq_ignore_ascii_case("py"))
        .unwrap_or(false);

    if is_python {
        let mut cmd = if let Some(stdbuf) = stdbuf_binary() {
            let mut c = Command::new(stdbuf);
            c.arg("-oL")
                .arg("-eL")
                .arg("python3")
                .arg("-u")
                .arg(script_path)
                .args(flags);
            c
        } else {
            let mut c = Command::new("python3");
            c.arg("-u").arg(script_path).args(flags);
            c
        };
        cmd.env("PYTHONUNBUFFERED", "1");
        cmd.env("PYTHONIOENCODING", "UTF-8");
        return cmd;
    }

    if let Some(stdbuf) = stdbuf_binary() {
        let mut cmd = Command::new(stdbuf);
        cmd.arg("-oL").arg("-eL").arg(script_path).args(flags);
        cmd
    } else {
        let mut cmd = Command::new(script_path);
        cmd.args(flags);
        cmd
    }
}

async fn stream_process_output<R>(mut reader: R, tx: mpsc::UnboundedSender<String>, prefix: &'static str)
where
    R: AsyncRead + Unpin,
{
    let mut buf = [0u8; 2048];
    let mut pending = String::new();

    loop {
        match reader.read(&mut buf).await {
            Ok(0) => {
                if !pending.is_empty() {
                    let line = std::mem::take(&mut pending);
                    let _ = tx.send(format!("{prefix}{line}"));
                }
                break;
            }
            Ok(n) => {
                let chunk = String::from_utf8_lossy(&buf[..n]);
                let mut ended_with_delim = false;
                for ch in chunk.chars() {
                    if ch == '\n' || ch == '\r' {
                        ended_with_delim = true;
                        if !pending.is_empty() {
                            let line = std::mem::take(&mut pending);
                            let _ = tx.send(format!("{prefix}{line}"));
                        }
                    } else {
                        ended_with_delim = false;
                        pending.push(ch);
                    }
                }
                if !ended_with_delim && !pending.is_empty() {
                    // Flush partial chunks too, so long-running commands update in near real-time.
                    let line = std::mem::take(&mut pending);
                    let _ = tx.send(format!("{prefix}{line}"));
                }
            }
            Err(e) => {
                if !pending.is_empty() {
                    let line = std::mem::take(&mut pending);
                    let _ = tx.send(format!("{prefix}{line}"));
                }
                let _ = tx.send(format!("{prefix}stream read error: {e}"));
                break;
            }
        }
    }
}

fn is_safe_method(method: &Method) -> bool {
    matches!(
        *method,
        Method::GET | Method::HEAD | Method::OPTIONS | Method::TRACE
    )
}

fn parse_host_from_authority(value: &str) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return None;
    }
    let authority = trimmed.rsplit('@').next().unwrap_or(trimmed).trim();
    if authority.is_empty() {
        return None;
    }
    if authority.starts_with('[') {
        let end = authority.find(']')?;
        return Some(authority[..=end].to_ascii_lowercase());
    }
    let host = authority
        .split(':')
        .next()
        .unwrap_or("")
        .trim()
        .to_ascii_lowercase();
    if host.is_empty() {
        None
    } else {
        Some(host)
    }
}

fn parse_host_from_url(value: &str) -> Option<String> {
    let trimmed = value.trim();
    let scheme_pos = trimmed.find("://")?;
    let rest = &trimmed[scheme_pos + 3..];
    let authority = rest.split('/').next().unwrap_or("");
    parse_host_from_authority(authority)
}

fn get_request_host(headers: &HeaderMap) -> Option<String> {
    headers
        .get(header::HOST)
        .and_then(|v| v.to_str().ok())
        .and_then(parse_host_from_authority)
}

fn get_source_host(headers: &HeaderMap) -> Option<String> {
    if let Some(origin) = headers.get(header::ORIGIN).and_then(|v| v.to_str().ok()) {
        if !origin.eq_ignore_ascii_case("null") {
            if let Some(host) = parse_host_from_url(origin) {
                return Some(host);
            }
        }
    }
    headers
        .get(header::REFERER)
        .and_then(|v| v.to_str().ok())
        .and_then(parse_host_from_url)
}

async fn csrf_protect(
    State(_state): State<AppState>,
    req: Request<Body>,
    next: Next,
) -> Response {
    if is_safe_method(req.method()) {
        return next.run(req).await;
    }

    let headers = req.headers();
    let csrf = headers
        .get(CSRF_HEADER_NAME)
        .and_then(|v| v.to_str().ok())
        .map(str::trim);
    if csrf != Some(CSRF_HEADER_VALUE) {
        return json_error(StatusCode::FORBIDDEN, "missing or invalid CSRF header");
    }

    let req_host = match get_request_host(headers) {
        Some(v) => v,
        None => return json_error(StatusCode::BAD_REQUEST, "missing Host header"),
    };
    if let Some(source_host) = get_source_host(headers) {
        if source_host != req_host {
            return json_error(StatusCode::FORBIDDEN, "Origin/Referer host mismatch");
        }
    }

    next.run(req).await
}

async fn fallback_handler(
    State(state): State<AppState>,
    axum::extract::OriginalUri(uri): axum::extract::OriginalUri,
) -> impl IntoResponse {
    if let Some(page) = route_to_page(uri.path()) {
        return serve_page(&state.webroot, page).await;
    }
    (StatusCode::NOT_FOUND, "Not Found").into_response()
}

async fn serve_page(webroot: &Path, page: &str) -> Response {
    let page_path = webroot.join(page);
    match tokio::fs::read_to_string(&page_path).await {
        Ok(body) => Html(body).into_response(),
        Err(_) => (StatusCode::NOT_FOUND, "page not found").into_response(),
    }
}

async fn read_config(state: &AppState) -> Result<Vec<CfgEntry>, String> {
    let data = tokio::fs::read_to_string(&state.config_path)
        .await
        .map_err(|e| e.to_string())?;
    let entries: Vec<CfgEntry> = serde_json::from_str(&data).map_err(|e| e.to_string())?;
    Ok(entries)
}

fn current_repo_root(state: &AppState) -> PathBuf {
    state
        .repo_root
        .read()
        .unwrap_or_else(|e| e.into_inner())
        .clone()
}

fn is_saturn_repo_root(path: &Path) -> bool {
    path.is_dir() && path.join(".git").exists() && path.join("update_manager").is_dir()
}

fn validate_saturn_repo_root(path: &Path) -> Result<(), String> {
    if !path.is_dir() {
        return Err("repo_root is not a directory".to_string());
    }
    if !path.join(".git").exists() {
        return Err("repo_root is not a git checkout".to_string());
    }
    if !path.join("update_manager").is_dir() {
        return Err("repo_root does not look like a Saturn checkout".to_string());
    }
    Ok(())
}

fn list_repo_root_candidates(active: &Path) -> Vec<String> {
    let mut set: BTreeSet<String> = BTreeSet::new();
    if is_saturn_repo_root(active) {
        set.insert(active.display().to_string());
    }

    if let Ok(home) = std::env::var("HOME") {
        for p in [PathBuf::from(&home).join("github/Saturn"), PathBuf::from(&home).join("github/saturn")] {
            if is_saturn_repo_root(&p) {
                set.insert(p.display().to_string());
            }
        }
    }

    if let Ok(home_entries) = fs::read_dir("/home") {
        for entry in home_entries.flatten() {
            let github = entry.path().join("github");
            if !github.is_dir() {
                continue;
            }
            if let Ok(repo_entries) = fs::read_dir(&github) {
                for repo in repo_entries.flatten() {
                    let repo_path = repo.path();
                    if is_saturn_repo_root(&repo_path) {
                        set.insert(repo_path.display().to_string());
                    }
                }
            }
        }
    }
    set.into_iter().collect()
}

async fn get_repo_root(State(state): State<AppState>) -> impl IntoResponse {
    Json(serde_json::json!({ "repo_root": current_repo_root(&state) }))
}

#[derive(Deserialize)]
struct SetRepoRootReq {
    repo_root: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct UpdatePolicy {
    owner: String,
    repo: String,
    remote: String,
    channel: String, // stable|beta|custom
    stable_ref: String,
    beta_ref: String,
    custom_ref: Option<String>,
    auto_snapshot: bool,
    keep_snapshots: usize,
    healthcheck_url: String,
    healthcheck_timeout_secs: u64,
}

impl Default for UpdatePolicy {
    fn default() -> Self {
        Self {
            owner: "Saturn".to_string(),
            repo: "Saturn".to_string(),
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
struct UpdateStartReq {
    channel: Option<String>,
    custom_ref: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct LastUpdateState {
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
struct ApplianceUpdateJob {
    id: String,
    status: String, // running|done|error|rolled_back|no_change
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

static APPLIANCE_UPDATE_JOB: OnceLock<Mutex<Option<ApplianceUpdateJob>>> = OnceLock::new();

fn appliance_update_slot() -> &'static Mutex<Option<ApplianceUpdateJob>> {
    APPLIANCE_UPDATE_JOB.get_or_init(|| Mutex::new(None))
}

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

fn is_safe_repo_part(value: &str) -> bool {
    !value.is_empty()
        && value
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '_' || c == '-')
}

fn is_safe_ref_name(value: &str) -> bool {
    !value.is_empty()
        && !value.starts_with('-')
        && !value.contains("..")
        && value
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '/' || c == '.' || c == '_' || c == '-')
}

fn expected_remote_url(policy: &UpdatePolicy) -> String {
    format!(
        "https://github.com/{}/{}.git",
        policy.owner.trim(),
        policy.repo.trim()
    )
}

fn normalize_update_policy(mut policy: UpdatePolicy, state: &AppState) -> UpdatePolicy {
    if !is_safe_repo_part(policy.owner.trim()) {
        policy.owner = "Saturn".to_string();
    } else {
        policy.owner = policy.owner.trim().to_string();
    }
    if !is_safe_repo_part(policy.repo.trim()) {
        policy.repo = "Saturn".to_string();
    } else {
        policy.repo = policy.repo.trim().to_string();
    }

    let remote = policy.remote.trim();
    if remote.is_empty() || !remote.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-' || c == '.') {
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

async fn load_update_policy(state: &AppState) -> Result<UpdatePolicy, String> {
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

async fn save_update_policy(state: &AppState, policy: UpdatePolicy) -> Result<UpdatePolicy, String> {
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
    let _ = tokio::fs::set_permissions(&state.update_policy_file, std::fs::Permissions::from_mode(0o640)).await;
    Ok(normalized)
}

async fn read_last_update_state(state: &AppState) -> Option<LastUpdateState> {
    let data = tokio::fs::read_to_string(&state.update_state_file).await.ok()?;
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
    let _ = tokio::fs::set_permissions(&state.update_state_file, std::fs::Permissions::from_mode(0o640)).await;
    Ok(())
}

fn select_channel_and_target(policy: &UpdatePolicy, req: &UpdateStartReq) -> Result<(String, String), String> {
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

async fn set_active_repo_root(state: &AppState, new_root: &Path) -> Result<(), String> {
    validate_saturn_repo_root(new_root)?;
    if let Some(parent) = state.repo_root_file.parent() {
        tokio::fs::create_dir_all(parent)
            .await
            .map_err(|e| format!("failed to create repo_root directory: {e}"))?;
    }
    tokio::fs::write(&state.repo_root_file, format!("{}\n", new_root.display()))
        .await
        .map_err(|e| format!("failed to persist repo_root: {e}"))?;
    let _ = tokio::fs::set_permissions(&state.repo_root_file, std::fs::Permissions::from_mode(0o640)).await;
    {
        let mut guard = state.repo_root.write().unwrap_or_else(|e| e.into_inner());
        *guard = new_root.to_path_buf();
    }
    Ok(())
}

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
        return Err(format!("git rev-parse {rev} failed: {}", output_error_text(&output)));
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
        return Err(format!("snapshot tar failed: {}", output_error_text(&output)));
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
            // Fallback cleanup if git worktree metadata is stale.
            tokio::fs::remove_dir_all(worktree)
                .await
                .map_err(|e| {
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
        Err(format!("health check failed: {}", output_error_text(&output)))
    }
}

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
        format!("Enforcing git remote {} -> {}", policy.remote, expected_remote),
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
        finish_appliance_update_job(&job_id, "error", format!("failed to create staging dir: {e}"));
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

    if let Err(e) = health_check_url(&policy.healthcheck_url, policy.healthcheck_timeout_secs).await {
        let _ = set_active_repo_root(&state, &active_root).await;
        let _ = remove_worktree(&active_root, &stage_dir).await;
        update_appliance_update_job(&job_id, |job| {
            job.rolled_back = true;
            job.new_repo_root = Some(active_root.display().to_string());
        });
        finish_appliance_update_job(&job_id, "error", format!("{e}; reverted to previous repo root"));
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
        append_appliance_update_log(&job_id, format!("warning: failed to persist update state: {e}"));
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
        append_appliance_update_log(&job_id, format!("warning: failed to prune staged worktrees: {e}"));
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

async fn get_update_policy(State(state): State<AppState>) -> Response {
    match load_update_policy(&state).await {
        Ok(policy) => Json(serde_json::json!({ "policy": policy })).into_response(),
        Err(e) => json_error(StatusCode::INTERNAL_SERVER_ERROR, &e),
    }
}

async fn set_update_policy(State(state): State<AppState>, Json(policy): Json<UpdatePolicy>) -> Response {
    match save_update_policy(&state, policy).await {
        Ok(policy) => Json(serde_json::json!({ "status": "ok", "policy": policy })).into_response(),
        Err(e) => json_error(StatusCode::INTERNAL_SERVER_ERROR, &e),
    }
}

async fn update_start(State(state): State<AppState>, Json(req): Json<UpdateStartReq>) -> Response {
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
    let (channel, target_ref) = match select_channel_and_target(&policy, &req) {
        Ok(v) => v,
        Err(e) => return json_error(StatusCode::BAD_REQUEST, &e),
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
        run_appliance_update(state_clone, job_id_clone, policy, channel, target_ref).await;
    });

    Json(serde_json::json!({
        "status": "started",
        "job_id": job_id,
    }))
    .into_response()
}

async fn update_status(State(state): State<AppState>) -> Response {
    let job = get_appliance_update_job();
    let last = read_last_update_state(&state).await;
    Json(serde_json::json!({
        "job": job,
        "last_update": last
    }))
    .into_response()
}

async fn update_rollback(State(state): State<AppState>) -> Response {
    if let Some(job) = get_appliance_update_job() {
        if job.status == "running" {
            return json_error(StatusCode::CONFLICT, "update in progress");
        }
    }

    let last = match read_last_update_state(&state).await {
        Some(v) => v,
        None => return json_error(StatusCode::NOT_FOUND, "no update state available for rollback"),
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

    let policy = load_update_policy(&state).await.unwrap_or_else(|_| normalize_update_policy(UpdatePolicy::default(), &state));
    if let Err(e) = health_check_url(&policy.healthcheck_url, policy.healthcheck_timeout_secs).await {
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

async fn list_repo_roots(State(state): State<AppState>) -> impl IntoResponse {
    let active = current_repo_root(&state);
    let roots = list_repo_root_candidates(&active);
    Json(serde_json::json!({
        "active": active,
        "repo_roots": roots
    }))
}

async fn set_repo_root(State(state): State<AppState>, Json(req): Json<SetRepoRootReq>) -> Response {
    let requested = req.repo_root.trim();
    if requested.is_empty() {
        return json_error(StatusCode::BAD_REQUEST, "repo_root is required");
    }

    let canonical = match tokio::fs::canonicalize(requested).await {
        Ok(p) => p,
        Err(e) => return json_error(StatusCode::BAD_REQUEST, &format!("invalid repo_root: {e}")),
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

fn json_error(status: StatusCode, message: &str) -> Response {
    (status, Json(serde_json::json!({ "message": message }))).into_response()
}

#[derive(Debug, Clone, Serialize)]
struct PiImageJob {
    id: String,
    status: String, // running|done|error
    progress: u8,
    message: String,
    file_path: Option<String>,
    size_bytes: Option<u64>,
    sha256: Option<String>,
    pid: Option<u32>,
    log: Vec<String>,
}

static PI_IMAGE_JOBS: OnceLock<Mutex<std::collections::HashMap<String, PiImageJob>>> = OnceLock::new();

fn jobs_map() -> &'static Mutex<std::collections::HashMap<String, PiImageJob>> {
    PI_IMAGE_JOBS.get_or_init(|| Mutex::new(std::collections::HashMap::new()))
}

fn set_job(job: PiImageJob) {
    let mut map = jobs_map().lock().unwrap();
    map.insert(job.id.clone(), job);
}

fn update_job(id: &str, f: impl FnOnce(&mut PiImageJob)) {
    let mut map = jobs_map().lock().unwrap();
    if let Some(j) = map.get_mut(id) {
        f(j);
    }
}

fn get_job(id: &str) -> Option<PiImageJob> {
    let map = jobs_map().lock().unwrap();
    map.get(id).cloned()
}

fn append_log(id: &str, line: String) {
    update_job(id, |j| {
        j.log.push(line);
        if j.log.len() > 200 {
            let excess = j.log.len() - 200;
            j.log.drain(0..excess);
        }
    });
}

#[derive(Debug, Clone, Serialize)]
struct PiCloneJob {
    id: String,
    status: String, // running|done|error|cancelled
    progress: u8,
    message: String,
    pid: Option<u32>,
    log: Vec<String>,
}

static PI_CLONE_JOBS: OnceLock<Mutex<std::collections::HashMap<String, PiCloneJob>>> = OnceLock::new();

fn clone_jobs_map() -> &'static Mutex<std::collections::HashMap<String, PiCloneJob>> {
    PI_CLONE_JOBS.get_or_init(|| Mutex::new(std::collections::HashMap::new()))
}

fn set_clone_job(job: PiCloneJob) {
    let mut map = clone_jobs_map().lock().unwrap();
    map.insert(job.id.clone(), job);
}

fn update_clone_job(id: &str, f: impl FnOnce(&mut PiCloneJob)) {
    let mut map = clone_jobs_map().lock().unwrap();
    if let Some(j) = map.get_mut(id) {
        f(j);
    }
}

fn get_clone_job(id: &str) -> Option<PiCloneJob> {
    let map = clone_jobs_map().lock().unwrap();
    map.get(id).cloned()
}

fn append_clone_log(id: &str, line: String) {
    update_clone_job(id, |j| {
        j.log.push(line);
        if j.log.len() > 200 {
            let excess = j.log.len() - 200;
            j.log.drain(0..excess);
        }
    });
}

#[derive(Deserialize)]
struct PiImageStartReq {
    shrink: Option<bool>,
    compress: Option<bool>,
    out_dir: Option<String>,
}

async fn pi_image_start(State(_state): State<AppState>, Json(req): Json<PiImageStartReq>) -> Response {
    let shrink = req.shrink.unwrap_or(true);
    let compress = req.compress.unwrap_or(false);
    let out_dir = req.out_dir.unwrap_or_else(|| "/tmp".to_string());

    if !Path::new(&out_dir).is_dir() {
        return json_error(StatusCode::BAD_REQUEST, "out_dir is not a directory");
    }

    let id = format!("piimg-{}-{}", std::process::id(), Local::now().format("%Y%m%d%H%M%S"));
    let job = PiImageJob {
        id: id.clone(),
        status: "running".to_string(),
        progress: 0,
        message: "starting".to_string(),
        file_path: None,
        size_bytes: None,
        sha256: None,
        pid: None,
        log: Vec::new(),
    };
    set_job(job.clone());

    tokio::spawn(async move {
        let mut cmd = Command::new("/opt/saturn-go/scripts/make_pi_image.sh");
        cmd.arg("--out-dir").arg(&out_dir);
        if !shrink {
            cmd.arg("--no-shrink");
        }
        if compress {
            cmd.arg("--compress");
        }
        cmd.stdout(std::process::Stdio::piped());
        cmd.stderr(std::process::Stdio::piped());

        let mut child = match cmd.spawn() {
            Ok(c) => c,
            Err(e) => {
                update_job(&id, |j| {
                    j.status = "error".to_string();
                    j.message = e.to_string();
                });
                return;
            }
        };

        update_job(&id, |j| j.pid = child.id());

        let stdout = child.stdout.take();
        let stderr = child.stderr.take();

        if let Some(out) = stdout {
            let id2 = id.clone();
            tokio::spawn(async move {
                let mut lines = BufReader::new(out).lines();
                while let Ok(Some(line)) = lines.next_line().await {
                    if let Some(p) = line.strip_prefix("Progress: ") {
                        if let Ok(v) = p.trim_end_matches('%').trim().parse::<u8>() {
                            update_job(&id2, |j| j.progress = v);
                        }
                    }
                    if let Some(done) = line.strip_prefix("Done: ") {
                        update_job(&id2, |j| j.file_path = Some(done.trim().to_string()));
                    }
                    update_job(&id2, |j| j.message = line.clone());
                    append_log(&id2, line);
                }
            });
        }

        if let Some(err) = stderr {
            let id2 = id.clone();
            tokio::spawn(async move {
                let mut lines = BufReader::new(err).lines();
                while let Ok(Some(line)) = lines.next_line().await {
                    let msg = format!("ERR: {line}");
                    update_job(&id2, |j| j.message = msg.clone());
                    append_log(&id2, msg);
                }
            });
        }

        let status = child.wait().await;
        match status {
            Ok(s) if s.success() => {
                // validate file
                let path = get_job(&id).and_then(|j| j.file_path);
                if let Some(p) = path {
                    let size = tokio::fs::metadata(&p).await.ok().map(|m| m.len());
                    let sha = Command::new("sha256sum").arg(&p).output().await.ok().and_then(|o| {
                        if o.status.success() {
                            let s = String::from_utf8_lossy(&o.stdout);
                            s.split_whitespace().next().map(|v| v.to_string())
                        } else { None }
                    });
                    update_job(&id, |j| {
                        j.status = "done".to_string();
                        j.progress = 100;
                        j.size_bytes = size;
                        j.sha256 = sha;
                        j.message = "done".to_string();
                        j.pid = None;
                    });
                } else {
                    update_job(&id, |j| {
                        j.status = "error".to_string();
                        j.message = "image path not found".to_string();
                        j.pid = None;
                    });
                }
            }
            Ok(s) => update_job(&id, |j| {
                j.status = "error".to_string();
                j.message = format!("image creation failed: {s}");
                j.pid = None;
            }),
            Err(e) => update_job(&id, |j| {
                j.status = "error".to_string();
                j.message = format!("image creation failed: {e}");
                j.pid = None;
            }),
        }
    });

    Json(serde_json::json!({ "job_id": job.id })).into_response()
}

#[derive(Deserialize)]
struct PiImageStatusQuery {
    job_id: String,
}

async fn pi_image_status(Query(q): Query<PiImageStatusQuery>) -> impl IntoResponse {
    if let Some(job) = get_job(&q.job_id) {
        Json(job).into_response()
    } else {
        json_error(StatusCode::NOT_FOUND, "job not found")
    }
}

async fn pi_image_cancel(Query(q): Query<PiImageStatusQuery>) -> impl IntoResponse {
    let job = match get_job(&q.job_id) {
        Some(j) => j,
        None => return json_error(StatusCode::NOT_FOUND, "job not found"),
    };
    if job.status != "running" {
        return json_error(StatusCode::BAD_REQUEST, "job not running");
    }
    if let Some(pid) = job.pid {
        let _ = Command::new("kill").arg("-15").arg(pid.to_string()).status().await;
    }
    update_job(&q.job_id, |j| {
        j.status = "cancelled".to_string();
        j.message = "cancelled".to_string();
        j.pid = None;
    });
    Json(serde_json::json!({ "status": "cancelled" })).into_response()
}

async fn pi_image_download(Query(q): Query<PiImageStatusQuery>) -> Result<Response, Response> {
    let job = match get_job(&q.job_id) {
        Some(j) => j,
        None => return Err(json_error(StatusCode::NOT_FOUND, "job not found")),
    };
    if job.status != "done" {
        return Err(json_error(StatusCode::BAD_REQUEST, "job not complete"));
    }
    let path = match job.file_path.clone() {
        Some(p) => p,
        None => return Err(json_error(StatusCode::BAD_REQUEST, "file not available")),
    };

    let file = tokio::fs::File::open(&path)
        .await
        .map_err(|e| json_error(StatusCode::INTERNAL_SERVER_ERROR, &e.to_string()))?;
    let stream = ReaderStream::new(file);
    let body = Body::from_stream(stream);

    let filename = Path::new(&path)
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("saturn-pi.img.gz")
        .to_string();

    let mut headers = HeaderMap::new();
    headers.insert("Content-Type", HeaderValue::from_static("application/octet-stream"));
    headers.insert(
        "Content-Disposition",
        HeaderValue::from_str(&format!("attachment; filename=\"{filename}\"")).unwrap_or_else(|_| {
            HeaderValue::from_static("attachment")
        }),
    );

    // best-effort cleanup after a short delay
    tokio::spawn(async move {
        tokio::time::sleep(Duration::from_secs(30)).await;
        let _ = tokio::fs::remove_file(&path).await;
    });

    Ok((headers, body).into_response())
}

#[derive(Serialize)]
struct PiDeviceInfo {
    name: String,
    path: String,
    size_bytes: u64,
    model: String,
}

async fn pi_devices() -> impl IntoResponse {
    let mut devices: Vec<PiDeviceInfo> = Vec::new();
    if let Ok(entries) = fs::read_dir("/sys/block") {
        for ent in entries.flatten() {
            let name = ent.file_name().to_string_lossy().to_string();
            let removable_path = ent.path().join("removable");
            let removable = fs::read_to_string(&removable_path)
                .ok()
                .map(|s| s.trim() == "1")
                .unwrap_or(false);
            if !removable {
                continue;
            }
            let size_path = ent.path().join("size");
            let sectors = fs::read_to_string(&size_path)
                .ok()
                .and_then(|s| s.trim().parse::<u64>().ok())
                .unwrap_or(0);
            let size_bytes = sectors.saturating_mul(512);
            let model_path = ent.path().join("device").join("model");
            let model = fs::read_to_string(&model_path)
                .ok()
                .map(|s| s.trim().to_string())
                .unwrap_or_else(|| "unknown".to_string());
            let path = format!("/dev/{name}");
            devices.push(PiDeviceInfo {
                name,
                path,
                size_bytes,
                model,
            });
        }
    }
    Json(serde_json::json!({ "devices": devices }))
}

#[derive(Deserialize)]
struct PiCloneStartReq {
    target: String,
}

async fn pi_clone_start(Json(req): Json<PiCloneStartReq>) -> Response {
    let target = req.target;
    if !target.starts_with("/dev/") {
        return json_error(StatusCode::BAD_REQUEST, "target must be a /dev path");
    }
    if target == "/dev/mmcblk0" {
        return json_error(StatusCode::BAD_REQUEST, "target cannot be source device");
    }

    // verify target is removable
    let name = target.trim_start_matches("/dev/");
    let removable_path = Path::new("/sys/block").join(name).join("removable");
    let removable = fs::read_to_string(&removable_path)
        .ok()
        .map(|s| s.trim() == "1")
        .unwrap_or(false);
    if !removable {
        return json_error(StatusCode::BAD_REQUEST, "target device is not removable");
    }

    let id = format!("piclone-{}-{}", std::process::id(), Local::now().format("%Y%m%d%H%M%S"));
    let job = PiCloneJob {
        id: id.clone(),
        status: "running".to_string(),
        progress: 0,
        message: "starting".to_string(),
        pid: None,
        log: Vec::new(),
    };
    set_clone_job(job.clone());

    tokio::spawn(async move {
        let mut cmd = Command::new("/opt/saturn-go/scripts/clone_pi_to_device.sh");
        cmd.arg("--target").arg(&target);
        cmd.stdout(std::process::Stdio::piped());
        cmd.stderr(std::process::Stdio::piped());

        let mut child = match cmd.spawn() {
            Ok(c) => c,
            Err(e) => {
                update_clone_job(&id, |j| {
                    j.status = "error".to_string();
                    j.message = e.to_string();
                });
                return;
            }
        };

        update_clone_job(&id, |j| j.pid = child.id());

        let stdout = child.stdout.take();
        let stderr = child.stderr.take();

        if let Some(out) = stdout {
            let id2 = id.clone();
            tokio::spawn(async move {
                let mut lines = BufReader::new(out).lines();
                while let Ok(Some(line)) = lines.next_line().await {
                    if let Some(p) = line.strip_prefix("Progress: ") {
                        if let Ok(v) = p.trim_end_matches('%').trim().parse::<u8>() {
                            update_clone_job(&id2, |j| j.progress = v);
                        }
                    }
                    update_clone_job(&id2, |j| j.message = line.clone());
                    append_clone_log(&id2, line);
                }
            });
        }

        if let Some(err) = stderr {
            let id2 = id.clone();
            tokio::spawn(async move {
                let mut lines = BufReader::new(err).lines();
                while let Ok(Some(line)) = lines.next_line().await {
                    let msg = format!("ERR: {line}");
                    update_clone_job(&id2, |j| j.message = msg.clone());
                    append_clone_log(&id2, msg);
                }
            });
        }

        let status = child.wait().await;
        match status {
            Ok(s) if s.success() => update_clone_job(&id, |j| {
                j.status = "done".to_string();
                j.progress = 100;
                j.message = "done".to_string();
                j.pid = None;
            }),
            Ok(s) => update_clone_job(&id, |j| {
                j.status = "error".to_string();
                j.message = format!("clone failed: {s}");
                j.pid = None;
            }),
            Err(e) => update_clone_job(&id, |j| {
                j.status = "error".to_string();
                j.message = format!("clone failed: {e}");
                j.pid = None;
            }),
        }
    });

    Json(serde_json::json!({ "job_id": job.id })).into_response()
}

async fn pi_clone_status(Query(q): Query<PiImageStatusQuery>) -> impl IntoResponse {
    if let Some(job) = get_clone_job(&q.job_id) {
        Json(job).into_response()
    } else {
        json_error(StatusCode::NOT_FOUND, "job not found")
    }
}

async fn pi_clone_cancel(Query(q): Query<PiImageStatusQuery>) -> impl IntoResponse {
    let job = match get_clone_job(&q.job_id) {
        Some(j) => j,
        None => return json_error(StatusCode::NOT_FOUND, "job not found"),
    };
    if job.status != "running" {
        return json_error(StatusCode::BAD_REQUEST, "job not running");
    }
    if let Some(pid) = job.pid {
        let _ = Command::new("kill").arg("-15").arg(pid.to_string()).status().await;
    }
    update_clone_job(&q.job_id, |j| {
        j.status = "cancelled".to_string();
        j.message = "cancelled".to_string();
        j.pid = None;
    });
    Json(serde_json::json!({ "status": "cancelled" })).into_response()
}

fn tree_stats_sync(root: &Path) -> (u64, u64, u64) {
    let mut files = 0u64;
    let mut dirs = 0u64;
    let mut bytes = 0u64;
    let mut stack = vec![root.to_path_buf()];
    while let Some(dir) = stack.pop() {
        dirs += 1;
        let entries = match std::fs::read_dir(&dir) {
            Ok(e) => e,
            Err(_) => continue,
        };
        for ent in entries.flatten() {
            let path = ent.path();
            match ent.file_type() {
                Ok(ft) if ft.is_dir() => stack.push(path),
                Ok(ft) if ft.is_file() => {
                    files += 1;
                    if let Ok(meta) = ent.metadata() {
                        bytes += meta.len();
                    }
                }
                _ => {}
            }
        }
    }
    (files, dirs, bytes)
}

async fn tree_stats(root: PathBuf) -> (u64, u64, u64) {
    tokio::task::spawn_blocking(move || tree_stats_sync(&root))
        .await
        .unwrap_or((0, 0, 0))
}

async fn get_versions(State(state): State<AppState>) -> impl IntoResponse {
    let entries = read_config(&state).await.unwrap_or_default();
    let mut versions = BTreeMap::new();
    for e in entries {
        let v = e.version.unwrap_or_else(|| "unknown".to_string());
        versions.insert(e.filename, v);
    }
    Json(serde_json::json!({ "versions": versions }))
}

async fn backup_full(State(state): State<AppState>) -> Result<Response, Response> {
    let repo_root = current_repo_root(&state);
    if !repo_root.is_dir() {
        return Err((StatusCode::BAD_REQUEST, "repo_root is not a directory").into_response());
    }

    let parent = repo_root.parent().unwrap_or(Path::new("/")).to_path_buf();
    let base = repo_root.file_name().and_then(|s| s.to_str()).unwrap_or("Saturn");

    let ts = Local::now().format("%Y%m%d-%H%M%S").to_string();
    let filename = format!("{base}.bak-{ts}.tar.gz");

    let mut cmd = Command::new("tar");
    cmd.arg("-C")
        .arg(&parent)
        .arg("-czf")
        .arg("-")
        .arg(base)
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped());

    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(e) => return Err((StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response()),
    };

    let stdout = match child.stdout.take() {
        Some(s) => s,
        None => return Err((StatusCode::INTERNAL_SERVER_ERROR, "tar stdout missing").into_response()),
    };
    let stderr = child.stderr.take();

    tokio::spawn(async move {
        if let Some(err) = stderr {
            let mut lines = BufReader::new(err).lines();
            while let Ok(Some(line)) = lines.next_line().await {
                error!("tar stderr: {line}");
            }
        }
        if let Ok(status) = child.wait().await {
            if !status.success() {
                error!("tar exited with status {status}");
            }
        }
    });

    let stream = ReaderStream::new(stdout);
    let body = Body::from_stream(stream);

    let mut headers = HeaderMap::new();
    headers.insert("Content-Type", HeaderValue::from_static("application/gzip"));
    headers.insert(
        "Content-Disposition",
        HeaderValue::from_str(&format!("attachment; filename=\"{filename}\"")).unwrap_or_else(|_| {
            HeaderValue::from_static("attachment")
        }),
    );

    Ok((headers, body).into_response())
}

#[derive(Deserialize, Default)]
struct RestoreQuery {
    dry_run: Option<String>,
}

fn parse_boolish(v: Option<String>) -> bool {
    match v.as_deref() {
        Some("1") | Some("true") | Some("yes") | Some("y") | Some("on") => true,
        _ => false,
    }
}

async fn restore_full(
    State(state): State<AppState>,
    Query(q): Query<RestoreQuery>,
    mut multipart: Multipart,
) -> Result<Response, Response> {
    let dry_run = parse_boolish(q.dry_run);
    let repo_root = current_repo_root(&state);

    let mut upload_path: Option<PathBuf> = None;
    let mut confirm: Option<String> = None;
    let mut upload_bytes = 0u64;

    while let Ok(Some(field)) = multipart.next_field().await {
        let name = field.name().map(|s| s.to_string()).unwrap_or_default();
        if name == "confirm" {
            let text = field.text().await.unwrap_or_default();
            confirm = Some(text.trim().to_string());
            continue;
        }
        if name != "file" {
            continue;
        }

        let ts = Local::now().format("%Y%m%d-%H%M%S").to_string();
        let tmp_name = format!("/tmp/saturn-upload-{ts}-{}", std::process::id());
        let path = PathBuf::from(tmp_name);
        let mut file = tokio::fs::File::create(&path)
            .await
            .map_err(|e| json_error(StatusCode::INTERNAL_SERVER_ERROR, &e.to_string()))?;

        let mut field = field;
        while let Ok(Some(chunk)) = field.chunk().await {
            upload_bytes = upload_bytes.saturating_add(chunk.len() as u64);
            if upload_bytes > state.restore_max_upload_bytes {
                let _ = tokio::fs::remove_file(&path).await;
                return Err(json_error(
                    StatusCode::PAYLOAD_TOO_LARGE,
                    &format!(
                        "archive too large (limit {} MB)",
                        state.restore_max_upload_bytes / 1024 / 1024
                    ),
                ));
            }
            tokio::io::AsyncWriteExt::write_all(&mut file, &chunk)
                .await
                .map_err(|e| json_error(StatusCode::INTERNAL_SERVER_ERROR, &e.to_string()))?;
        }
        upload_path = Some(path);
    }

    let upload_path = match upload_path {
        Some(p) => p,
        None => return Err(json_error(StatusCode::BAD_REQUEST, "missing file")),
    };

    if !dry_run {
        if confirm.as_deref() != Some("RESTORE") {
            let _ = tokio::fs::remove_file(&upload_path).await;
            return Err(json_error(StatusCode::BAD_REQUEST, "confirm token required"));
        }
    }

    if let Err(e) = validate_saturn_repo_root(&repo_root) {
        let _ = tokio::fs::remove_file(&upload_path).await;
        return Err(json_error(StatusCode::BAD_REQUEST, &e));
    }

    // Pre-validate tar contents for traversal attempts.
    let list_out = Command::new("tar")
        .arg("-tzf")
        .arg(&upload_path)
        .output()
        .await
        .map_err(|e| json_error(StatusCode::BAD_REQUEST, &e.to_string()))?;
    if !list_out.status.success() {
        let msg = String::from_utf8_lossy(&list_out.stderr).trim().to_string();
        let _ = tokio::fs::remove_file(&upload_path).await;
        return Err(json_error(StatusCode::BAD_REQUEST, &format!("tar list failed: {msg}")));
    }
    for line in String::from_utf8_lossy(&list_out.stdout).lines() {
        if line.starts_with('/') || line.contains("..") {
            let _ = tokio::fs::remove_file(&upload_path).await;
            return Err(json_error(StatusCode::BAD_REQUEST, "archive contains unsafe paths"));
        }
    }

    let ts = Local::now().format("%Y%m%d-%H%M%S").to_string();
    let extract_dir = PathBuf::from(format!("/tmp/saturn-restore-{ts}-{}", std::process::id()));
    tokio::fs::create_dir_all(&extract_dir)
        .await
        .map_err(|e| json_error(StatusCode::INTERNAL_SERVER_ERROR, &e.to_string()))?;

    let status = Command::new("tar")
        .arg("-xzf")
        .arg(&upload_path)
        .arg("-C")
        .arg(&extract_dir)
        .status()
        .await
        .map_err(|e| json_error(StatusCode::INTERNAL_SERVER_ERROR, &e.to_string()))?;
    if !status.success() {
        let _ = tokio::fs::remove_file(&upload_path).await;
        let _ = tokio::fs::remove_dir_all(&extract_dir).await;
        return Err(json_error(StatusCode::BAD_REQUEST, "extract failed"));
    }

    let mut entries = tokio::fs::read_dir(&extract_dir)
        .await
        .map_err(|e| json_error(StatusCode::INTERNAL_SERVER_ERROR, &e.to_string()))?;
    let mut top_dirs: Vec<PathBuf> = Vec::new();
    while let Ok(Some(ent)) = entries.next_entry().await {
        let path = ent.path();
        if path.is_dir() {
            top_dirs.push(path);
        }
    }
    if top_dirs.len() != 1 {
        let _ = tokio::fs::remove_file(&upload_path).await;
        let _ = tokio::fs::remove_dir_all(&extract_dir).await;
        return Err(json_error(StatusCode::BAD_REQUEST, "archive must contain a single top-level directory"));
    }
    let extracted_root = top_dirs.remove(0);

    if dry_run {
        let (files, dirs, bytes) = tree_stats(extracted_root.clone()).await;
        let _ = tokio::fs::remove_file(&upload_path).await;
        let _ = tokio::fs::remove_dir_all(&extract_dir).await;
        return Ok(Json(serde_json::json!({
            "status": "ok",
            "dry_run": true,
            "extracted_root": extracted_root,
            "files": files,
            "dirs": dirs,
            "bytes": bytes
        }))
        .into_response());
    }

    tokio::fs::create_dir_all(&repo_root)
        .await
        .map_err(|e| json_error(StatusCode::INTERNAL_SERVER_ERROR, &e.to_string()))?;

    let rsync_status = Command::new("rsync")
        .arg("-a")
        .arg("--delete")
        .arg(format!("{}/", extracted_root.display()))
        .arg(format!("{}/", repo_root.display()))
        .status()
        .await
        .map_err(|e| json_error(StatusCode::INTERNAL_SERVER_ERROR, &e.to_string()))?;

    let _ = tokio::fs::remove_file(&upload_path).await;
    let _ = tokio::fs::remove_dir_all(&extract_dir).await;

    if !rsync_status.success() {
        return Err(json_error(StatusCode::INTERNAL_SERVER_ERROR, "rsync failed"));
    }

    Ok(Json(serde_json::json!({ "status": "ok" })).into_response())
}

async fn get_scripts(State(state): State<AppState>) -> impl IntoResponse {
    let entries = read_config(&state).await.unwrap_or_default();
    if entries.is_empty() {
        return Json(serde_json::json!({
            "scripts": {
                "System": [
                    { "filename":"echo-hello.sh", "name":"Echo Hello", "description":"Demo script" }
                ]
            },
            "warnings": ["config.json missing or invalid; showing demo"]
        }));
    }

    let mut grouped: BTreeMap<String, Vec<serde_json::Value>> = BTreeMap::new();
    for e in entries {
        let cat = e.category.clone().unwrap_or_else(|| "Scripts".to_string());
        grouped
            .entry(cat)
            .or_default()
            .push(serde_json::json!({
                "filename": e.filename,
                "name": e.name.unwrap_or_default(),
                "description": e.description.unwrap_or_default(),
            }));
    }

    Json(serde_json::json!({ "scripts": grouped, "warnings": [] }))
}

async fn get_flags(State(state): State<AppState>, Query(q): Query<FlagsQuery>) -> impl IntoResponse {
    let script = q.script.unwrap_or_default();
    let entries = match read_config(&state).await {
        Ok(v) => v,
        Err(_) => {
            return Json(serde_json::json!({
                "flags": [],
                "error": "config.json not found or invalid",
                "warning": "Using empty flags"
            }));
        }
    };

    for e in entries {
        if e.filename == script {
            return Json(serde_json::json!({ "flags": e.flags.unwrap_or_default() }));
        }
    }
    Json(serde_json::json!({ "flags": [] }))
}

async fn get_fpga_images() -> impl IntoResponse {
    fn list_images(dir: &Path) -> Vec<String> {
        let mut images: Vec<String> = Vec::new();
        if let Ok(entries) = fs::read_dir(dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
                    if matches!(ext, "bin" | "rbf" | "bit") {
                        if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                            images.push(name.to_string());
                        }
                    }
                }
            }
        }
        images.sort();
        images
    }

    let mut candidates: Vec<PathBuf> = Vec::new();
    if let Ok(dir) = std::env::var("SATURN_FPGA_DIR") {
        candidates.push(PathBuf::from(dir));
    }

    if let Ok(home) = std::env::var("HOME") {
        candidates.push(PathBuf::from(&home).join("github/Saturn/FPGA"));
        candidates.push(PathBuf::from(&home).join("github/saturn/FPGA"));
    }

    if let Ok(home_entries) = fs::read_dir("/home") {
        for entry in home_entries.flatten() {
            candidates.push(entry.path().join("github/Saturn/FPGA"));
            candidates.push(entry.path().join("github/saturn/FPGA"));
        }
    }

    candidates.push(PathBuf::from("/opt/saturn-go/FPGA"));

    let mut selected: Option<PathBuf> = None;
    let mut images: Vec<String> = Vec::new();
    let mut checked: Vec<String> = Vec::new();

    for dir in candidates {
        let dir_str = dir.to_string_lossy().to_string();
        if checked.iter().any(|d| d == &dir_str) {
            continue;
        }
        checked.push(dir_str);
        if dir.is_dir() {
            let listed = list_images(&dir);
            if selected.is_none() {
                selected = Some(dir.clone());
                images = listed.clone();
            }
            if !listed.is_empty() {
                selected = Some(dir);
                images = listed;
                break;
            }
        }
    }

    let warning = if selected.is_none() {
        Some("No FPGA directory found (set SATURN_FPGA_DIR or place images in ~/github/Saturn/FPGA)".to_string())
    } else if images.is_empty() {
        Some("FPGA directory found but no .bin/.rbf/.bit images were found".to_string())
    } else {
        None
    };

    Json(serde_json::json!({
        "dir": selected,
        "images": images,
        "checked": checked,
        "warning": warning
    }))
}

async fn run_sse(
    State(_state): State<AppState>,
    multipart: Multipart,
) -> Result<Response, Response> {
    let (script, flags) = match parse_multipart(multipart).await {
        Ok(v) => v,
        Err(resp) => return Err(resp),
    };

    if script.is_empty() || script.contains("..") || script.contains('/') || script.contains('\\') {
        return Err((StatusCode::BAD_REQUEST, "invalid script").into_response());
    }

    let script_path = PathBuf::from("/opt/saturn-go/scripts").join(&script);
    if tokio::fs::metadata(&script_path).await.is_err() {
        return Err((StatusCode::NOT_FOUND, "script not found").into_response());
    }

    let (tx, rx) = mpsc::unbounded_channel::<String>();

    let start_line = format!("Running {} {}", script, flags.join(" "));
    let _ = tx.send(start_line);

    let mut cmd = build_script_command(&script_path, &flags);

    cmd.stdout(std::process::Stdio::piped());
    cmd.stderr(std::process::Stdio::piped());

    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(e) => return Err((StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response()),
    };

    if let Some(stdout) = child.stdout.take() {
        let tx_out = tx.clone();
        tokio::spawn(async move {
            stream_process_output(stdout, tx_out, "").await;
        });
    }

    if let Some(stderr) = child.stderr.take() {
        let tx_err = tx.clone();
        tokio::spawn(async move {
            stream_process_output(stderr, tx_err, "ERR: ").await;
        });
    }

    tokio::spawn(async move {
        match child.wait().await {
            Ok(status) if status.success() => {
                let _ = tx.send("Done".to_string());
            }
            Ok(status) => {
                let _ = tx.send(format!("Error: {status}"));
            }
            Err(e) => {
                let _ = tx.send(format!("Error: {e}"));
            }
        }
    });

    let stream = UnboundedReceiverStream::new(rx)
        .map(|line| Ok::<Event, std::convert::Infallible>(Event::default().data(line)));
    let sse = Sse::new(stream).keep_alive(KeepAlive::new().interval(Duration::from_secs(5)));
    let mut resp = sse.into_response();
    resp.headers_mut()
        .insert(header::CACHE_CONTROL, HeaderValue::from_static("no-cache"));
    resp.headers_mut().insert(
        header::HeaderName::from_static("x-accel-buffering"),
        HeaderValue::from_static("no"),
    );
    Ok(resp)
}

async fn parse_multipart(mut multipart: Multipart) -> Result<(String, Vec<String>), Response> {
    let mut script = String::new();
    let mut flags = Vec::new();

    while let Ok(Some(field)) = multipart.next_field().await {
        let name = field.name().map(|s| s.to_string()).unwrap_or_default();
        let text = field.text().await.unwrap_or_default();
        if name == "script" {
            script = text;
        } else if name == "flags" {
            flags.push(text);
        }
    }

    if script.is_empty() {
        return Err((StatusCode::BAD_REQUEST, "missing script").into_response());
    }

    Ok((script, flags))
}

async fn no_content() -> impl IntoResponse {
    StatusCode::NO_CONTENT
}

#[derive(Deserialize)]
struct PasswordForm {
    new_password: String,
}

async fn run_htpasswd(new_password: &str, use_sudo: bool) -> Result<std::process::Output, std::io::Error> {
    let mut cmd = if use_sudo {
        let mut c = Command::new("sudo");
        c.arg("-n").arg("htpasswd");
        c
    } else {
        Command::new("htpasswd")
    };

    cmd.arg("-i")
        .arg("/etc/nginx/.htpasswd")
        .arg("admin")
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped());

    let mut child = cmd.spawn()?;
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(new_password.as_bytes()).await?;
        stdin.write_all(b"\n").await?;
    }
    child.wait_with_output().await
}

fn output_error_text(output: &std::process::Output) -> String {
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if !stderr.is_empty() {
        stderr
    } else if !stdout.is_empty() {
        stdout
    } else {
        format!("{}", output.status)
    }
}

async fn change_password(
    State(_state): State<AppState>,
    axum::extract::Form(form): axum::extract::Form<PasswordForm>,
) -> impl IntoResponse {
    if form.new_password.len() < 5 {
        return Json(serde_json::json!({ "status":"error", "message":"min length 5" }));
    }

    match run_htpasswd(&form.new_password, false).await {
        Ok(out) if out.status.success() => {
            return Json(serde_json::json!({ "status":"success" }));
        }
        Ok(_out) => {
            // Common case in service mode: no write permission for /etc/nginx/.htpasswd.
            // Retry with non-interactive sudo (works with sudoers NOPASSWD).
        }
        Err(_e) => {
            // Retry below; covers command permission/path issues where sudo may still work.
        }
    };

    match run_htpasswd(&form.new_password, true).await {
        Ok(out) if out.status.success() => Json(serde_json::json!({ "status":"success" })),
        Ok(out) => {
            let detail = output_error_text(&out);
            let msg = if detail.contains("a password is required")
                || detail.contains("no tty present")
                || detail.contains("is not allowed to execute")
            {
                "Password change requires sudo permission for htpasswd (configure NOPASSWD for this command).".to_string()
            } else {
                format!("htpasswd failed: {detail}")
            };
            Json(serde_json::json!({ "status":"error", "message": msg }))
        }
        Err(e) => Json(serde_json::json!({ "status":"error", "message": e.to_string() })),
    }
}

async fn exit_server() -> impl IntoResponse {
    tokio::spawn(async {
        tokio::time::sleep(Duration::from_millis(200)).await;
        std::process::exit(0);
    });
    Json(serde_json::json!({ "status":"shutting down" }))
}

#[derive(Deserialize, Default)]
struct ProcQuery {
    proc_sort: Option<String>,      // cpu|mem|pid|user|command|start
    proc_order: Option<String>,     // asc|desc
    proc_user: Option<String>,      // exact match
    proc_regex: Option<String>,     // regex on command
    proc_top: Option<usize>,
    proc_page: Option<usize>,
    proc_page_size: Option<usize>,
}

async fn get_system_data(Query(q): Query<ProcQuery>) -> impl IntoResponse {
    let cpu = match read_per_core_cpu().await {
        Ok(v) => v,
        Err(e) => {
            error!("cpu read error: {e}");
            vec![0.0]
        }
    };

    let mut sys = System::new();
    sys.refresh_memory();
    sys.refresh_cpu();
    sys.refresh_processes();

    let total_mem_kb = sys.total_memory() as f64;
    let avail_mem_kb = sys.available_memory() as f64;
    let used_mem_kb = (total_mem_kb - avail_mem_kb).max(0.0);

    let m_total_gb = total_mem_kb / 1024.0 / 1024.0;
    let m_used_gb = used_mem_kb / 1024.0 / 1024.0;
    let m_percent = if total_mem_kb > 0.0 {
        (used_mem_kb / total_mem_kb) * 100.0
    } else {
        0.0
    };

    let mut disks = Disks::new_with_refreshed_list();
    disks.refresh();
    let (d_total_gb, d_used_gb, d_percent) = pick_root_disk(&disks);
    let (d_read_bytes, d_write_bytes) = read_disk_io_totals();
    let (d_read_bps, d_write_bps) = calc_rate("disk", d_read_bytes, d_write_bytes);

    let mut networks = Networks::new_with_refreshed_list();
    networks.refresh();
    let (mut sent, mut recv) = sum_networks(&networks);
    if sent == 0 && recv == 0 {
        let (psent, precv) = read_net_dev_totals();
        if psent > 0 || precv > 0 {
            sent = psent;
            recv = precv;
        }
    }
    let (tx_bps, rx_bps) = calc_rate("net", sent, recv);

    let procs = list_procs_sysinfo(&sys, total_mem_kb, &q);
    let load = sysinfo::System::load_average();
    let uptime = sysinfo::System::uptime();
    let cpu_temp = read_cpu_temp_c();
    let swap_total_gb = sys.total_swap() as f64 / 1024.0 / 1024.0;
    let swap_used_gb = sys.used_swap() as f64 / 1024.0 / 1024.0;
    let swap_percent = if sys.total_swap() > 0 {
        (sys.used_swap() as f64 / sys.total_swap() as f64) * 100.0
    } else {
        0.0
    };

    Json(serde_json::json!({
        "cpu": cpu,
        "memory": { "percent": m_percent, "used": m_used_gb, "total": m_total_gb },
        "swap": { "percent": swap_percent, "used": swap_used_gb, "total": swap_total_gb },
        "disk": { "percent": d_percent, "used": d_used_gb, "total": d_total_gb, "read_bytes": d_read_bytes, "write_bytes": d_write_bytes, "read_bps": d_read_bps, "write_bps": d_write_bps },
        "network": { "sent": sent, "recv": recv, "tx_bps": tx_bps, "rx_bps": rx_bps },
        "load": { "one": load.one, "five": load.five, "fifteen": load.fifteen },
        "uptime": { "seconds": uptime },
        "temperature": { "cpu_c": cpu_temp },
        "processes": procs
    }))
}

async fn network_test() -> impl IntoResponse {
    // Generate server-side traffic and report measured throughput
    let (sent0, recv0) = get_net_totals();
    let start = Instant::now();

    let urls = [
        "https://ash-speed.hetzner.com/10MB.bin",
        "https://proof.ovh.net/files/10Mb.dat",
        "https://speed.cloudflare.com/__down?bytes=10000000",
    ];
    let mut last_err = String::new();
    let mut ok = false;

    for url in urls {
        let out = Command::new("curl")
            .arg("-L")
            .arg("--silent")
            .arg("--show-error")
            .arg("--fail")
            .arg("--max-redirs")
            .arg("5")
            .arg("--output")
            .arg("/dev/null")
            .arg("--connect-timeout")
            .arg("5")
            .arg("--max-time")
            .arg("30")
            .arg(url)
            .output()
            .await;

        match out {
            Ok(o) if o.status.success() => {
                ok = true;
                break;
            }
            Ok(o) => {
                let stderr = String::from_utf8_lossy(&o.stderr).trim().to_string();
                if stderr.is_empty() {
                    last_err = format!("{} on {}", o.status, url);
                } else {
                    last_err = format!("{} on {} ({})", o.status, url, stderr);
                }
            }
            Err(e) => {
                last_err = format!("{} on {}", e, url);
            }
        }
    }

    let elapsed = start.elapsed().as_secs_f64().max(0.001);
    let (sent1, recv1) = get_net_totals();

    if ok {
        let tx_bps = ((sent1.saturating_sub(sent0)) as f64 / elapsed) as u64;
        let rx_bps = ((recv1.saturating_sub(recv0)) as f64 / elapsed) as u64;
        Json(serde_json::json!({
            "tx_bps": tx_bps,
            "rx_bps": rx_bps,
            "seconds": elapsed
        }))
    } else {
        Json(serde_json::json!({
            "error": format!("curl test failed: {}", if last_err.is_empty() { "no route succeeded".to_string() } else { last_err })
        }))
    }
}

#[derive(Deserialize)]
struct KillQuery {
    sig: Option<String>, // term|kill
}

async fn kill_process(
    axum::extract::Path(pid): axum::extract::Path<i32>,
    Query(kq): Query<KillQuery>,
) -> impl IntoResponse {
    if pid <= 0 {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({ "message": "bad pid" })),
        )
            .into_response();
    }
    if is_protected_pid(pid) {
        return (
            StatusCode::FORBIDDEN,
            Json(serde_json::json!({ "message": "Protected process" })),
        )
            .into_response();
    }
    let sig = kq.sig.as_deref().unwrap_or("term");
    let signal = match sig {
        "kill" => "-9",
        "term" => "-15",
        _ => {
            return (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({ "message": "invalid signal" })),
            )
                .into_response()
        }
    };

    let output = Command::new("kill")
        .arg(signal)
        .arg(pid.to_string())
        .output()
        .await;

    match output {
        Ok(o) if o.status.success() => (
            StatusCode::OK,
            Json(serde_json::json!({ "message": "OK" })),
        )
            .into_response(),
        Ok(o) => {
            let stderr = String::from_utf8_lossy(&o.stderr).trim().to_string();
            let stderr_lc = stderr.to_lowercase();
            let status = if stderr_lc.contains("no such process") {
                StatusCode::NOT_FOUND
            } else if stderr_lc.contains("operation not permitted") {
                StatusCode::FORBIDDEN
            } else {
                StatusCode::BAD_REQUEST
            };
            let msg = if stderr.is_empty() {
                format!("Failed: {}", o.status)
            } else {
                format!("Failed: {stderr}")
            };
            (status, Json(serde_json::json!({ "message": msg }))).into_response()
        }
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({ "message": format!("Failed: {e}") })),
        )
            .into_response(),
    }
}

async fn read_per_core_cpu() -> Result<Vec<f64>, String> {
    let a = read_proc_stat().await?;
    tokio::time::sleep(Duration::from_millis(120)).await;
    let b = read_proc_stat().await?;
    if a.len() != b.len() || a.is_empty() {
        return Ok(vec![0.0]);
    }

    let mut out = Vec::with_capacity(a.len());
    for (sa, sb) in a.iter().zip(b.iter()) {
        let d_idle = (sb.idle - sa.idle) as f64;
        let d_total = (sb.total - sa.total) as f64;
        let mut p = if d_total > 0.0 { (1.0 - d_idle / d_total) * 100.0 } else { 0.0 };
        if p < 0.0 {
            p = 0.0;
        } else if p > 100.0 {
            p = 100.0;
        }
        out.push(p);
    }
    Ok(out)
}

#[derive(Clone, Copy)]
struct CpuSnap {
    idle: u64,
    total: u64,
}

async fn read_proc_stat() -> Result<Vec<CpuSnap>, String> {
    let data = tokio::fs::read_to_string("/proc/stat")
        .await
        .map_err(|e| e.to_string())?;
    let mut res = Vec::new();
    for line in data.lines() {
        if !line.starts_with("cpu") || line.starts_with("cpu ") {
            continue;
        }
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() < 6 {
            continue;
        }
        let mut vals = Vec::new();
        for p in &parts[1..] {
            if let Ok(v) = p.parse::<u64>() {
                vals.push(v);
            }
        }
        if vals.len() < 5 {
            continue;
        }
        let idle = vals[3] + vals[4];
        let total: u64 = vals.iter().sum();
        res.push(CpuSnap { idle, total });
    }
    Ok(res)
}

fn pick_root_disk(disks: &Disks) -> (f64, f64, f64) {
    let mut total = 0.0;
    let mut used = 0.0;

    if let Some(d) = disks.iter().find(|d| d.mount_point() == Path::new("/")) {
        total = d.total_space() as f64;
        used = (d.total_space() - d.available_space()) as f64;
    } else if let Some(d) = disks.iter().next() {
        total = d.total_space() as f64;
        used = (d.total_space() - d.available_space()) as f64;
    }

    let total_gb = total / 1024.0 / 1024.0 / 1024.0;
    let used_gb = used / 1024.0 / 1024.0 / 1024.0;
    let percent = if total > 0.0 { (used / total) * 100.0 } else { 0.0 };
    (total_gb, used_gb, percent)
}

fn sum_networks(networks: &Networks) -> (u64, u64) {
    let mut sent = 0u64;
    let mut recv = 0u64;
    for (_name, data) in networks.iter() {
        sent += data.transmitted();
        recv += data.received();
    }
    (sent, recv)
}

fn get_net_totals() -> (u64, u64) {
    let mut networks = Networks::new_with_refreshed_list();
    networks.refresh();
    let (sent, recv) = sum_networks(&networks);
    if sent == 0 && recv == 0 {
        return read_net_dev_totals();
    }
    (sent, recv)
}

fn read_net_dev_totals() -> (u64, u64) {
    // /proc/net/dev provides byte counters for interfaces
    if let Ok(data) = fs::read_to_string("/proc/net/dev") {
        let mut sent = 0u64;
        let mut recv = 0u64;
        for line in data.lines().skip(2) {
            // iface: bytes ... tx_bytes ...
            let parts: Vec<&str> = line.split(':').collect();
            if parts.len() != 2 {
                continue;
            }
            let stats: Vec<&str> = parts[1].split_whitespace().collect();
            if stats.len() >= 16 {
                recv += stats[0].parse::<u64>().unwrap_or(0);
                sent += stats[8].parse::<u64>().unwrap_or(0);
            }
        }
        return (sent, recv);
    }
    (0, 0)
}

fn read_cpu_temp_c() -> Option<f64> {
    // Try common thermal zones
    if let Ok(entries) = fs::read_dir("/sys/class/thermal") {
        for entry in entries.flatten() {
            let path = entry.path().join("temp");
            if let Ok(s) = fs::read_to_string(&path) {
                if let Ok(raw) = s.trim().parse::<f64>() {
                    // Most systems report millideg C
                    let c = if raw > 1000.0 { raw / 1000.0 } else { raw };
                    if c > 0.0 {
                        return Some(c);
                    }
                }
            }
        }
    }
    None
}

fn read_disk_io_totals() -> (u64, u64) {
    // Find device backing '/'
    let dev = match root_device_name() {
        Some(d) => d,
        None => return (0, 0),
    };
    if let Ok(data) = fs::read_to_string("/proc/diskstats") {
        for line in data.lines() {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() < 14 {
                continue;
            }
            if parts[2] == dev {
                // sectors read (field 6), sectors written (field 10)
                let sr = parts[5].parse::<u64>().unwrap_or(0);
                let sw = parts[9].parse::<u64>().unwrap_or(0);
                // assume 512 bytes/sector
                return (sr.saturating_mul(512), sw.saturating_mul(512));
            }
        }
    }
    (0, 0)
}

fn root_device_name() -> Option<String> {
    if let Ok(data) = fs::read_to_string("/proc/mounts") {
        for line in data.lines() {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 2 && parts[1] == "/" {
                let dev = parts[0];
                if dev.starts_with("/dev/") {
                    return Some(base_device_name(dev));
                }
            }
        }
    }
    None
}

fn base_device_name(dev: &str) -> String {
    let name = dev.trim_start_matches("/dev/");
    if name.starts_with("nvme") && name.contains('p') {
        // nvme0n1p2 -> nvme0n1
        return name.split('p').next().unwrap_or(name).to_string();
    }
    if name.starts_with("mmcblk") && name.contains('p') {
        return name.split('p').next().unwrap_or(name).to_string();
    }
    // strip trailing digits (sda1 -> sda)
    let trimmed = name.trim_end_matches(|c: char| c.is_ascii_digit());
    if trimmed.is_empty() { name.to_string() } else { trimmed.to_string() }
}

fn calc_rate(kind: &str, a: u64, b: u64) -> (u64, u64) {
    static LAST: OnceLock<Mutex<std::collections::HashMap<String, (u64, u64, u128)>>> = OnceLock::new();
    let map = LAST.get_or_init(|| Mutex::new(std::collections::HashMap::new()));
    let mut guard = map.lock().unwrap();

    let now_ms = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_millis();
    let entry = guard.entry(kind.to_string()).or_insert((a, b, now_ms));
    let (la, lb, lt) = *entry;
    let dt_ms = (now_ms.saturating_sub(lt)).max(1);

    let ra = a.saturating_sub(la) * 1000 / dt_ms as u64;
    let rb = b.saturating_sub(lb) * 1000 / dt_ms as u64;

    *entry = (a, b, now_ms);
    (ra, rb)
}

fn list_procs_sysinfo(sys: &System, total_mem_kb: f64, q: &ProcQuery) -> Vec<serde_json::Value> {
    let mut out: Vec<ProcInfo> = Vec::new();
    for (pid, proc_) in sys.processes() {
        let pid_i32 = pid.as_u32() as i32;
        let user = proc_
            .user_id()
            .and_then(|u| u.to_string().parse::<u32>().ok())
            .and_then(|uid| get_user_by_uid(uid))
            .and_then(|u| u.name().to_str().map(|s| s.to_string()))
            .unwrap_or_else(|| "unknown".to_string());
        let cmd = if !proc_.cmd().is_empty() {
            proc_.cmd().join(" ")
        } else if let Some(exe) = proc_.exe() {
            if !exe.as_os_str().is_empty() {
                exe.display().to_string()
            } else {
                proc_.name().to_string()
            }
        } else {
            proc_.name().to_string()
        };
        let cwd = proc_.cwd().map(|p| p.display().to_string()).unwrap_or_default();
        let start_time = proc_.start_time(); // seconds since boot

        let mem_kb = proc_.memory() as f64;
        let mem_pct = if total_mem_kb > 0.0 { (mem_kb / total_mem_kb) * 100.0 } else { 0.0 };
        let cpu = proc_.cpu_usage() as f64;

        out.push(ProcInfo {
            pid: pid_i32,
            user,
            cpu,
            mem_pct,
            mem_mb: mem_kb / 1024.0,
            command: cmd,
            cwd,
            start_time,
        });
    }

    // Filters
    if let Some(u) = &q.proc_user {
        out.retain(|p| p.user == *u);
    }
    if let Some(r) = &q.proc_regex {
        if let Ok(re) = Regex::new(r) {
            out.retain(|p| re.is_match(&p.command));
        }
    }

    // Sorting
    let sort = q.proc_sort.as_deref().unwrap_or("cpu");
    let desc = q.proc_order.as_deref().unwrap_or("desc") != "asc";
    out.sort_by(|a, b| match sort {
        "mem" => a.mem_pct.partial_cmp(&b.mem_pct).unwrap_or(std::cmp::Ordering::Equal),
        "pid" => a.pid.cmp(&b.pid),
        "user" => a.user.cmp(&b.user),
        "command" => a.command.cmp(&b.command),
        "start" => a.start_time.cmp(&b.start_time),
        _ => a.cpu.partial_cmp(&b.cpu).unwrap_or(std::cmp::Ordering::Equal),
    });
    if desc {
        out.reverse();
    }

    // Pagination / top
    if let Some(top) = q.proc_top {
        if out.len() > top {
            out.truncate(top);
        }
    } else if let (Some(page), Some(page_size)) = (q.proc_page, q.proc_page_size) {
        let start = page.saturating_mul(page_size);
        out = out.into_iter().skip(start).take(page_size).collect();
    } else if out.len() > 20 {
        out.truncate(20);
    }

    out.into_iter()
        .map(|p| {
            serde_json::json!({
                "pid": p.pid,
                "user": p.user,
                "cpu": p.cpu,
                "memory": p.mem_pct,
                "mem_mb": p.mem_mb,
                "command": p.command,
                "cwd": p.cwd,
                "start_time": p.start_time,
            })
        })
        .collect()
}

#[derive(Debug)]
struct ProcInfo {
    pid: i32,
    user: String,
    cpu: f64,
    mem_pct: f64,
    mem_mb: f64,
    command: String,
    cwd: String,
    start_time: u64,
}

fn is_protected_pid(pid: i32) -> bool {
    if pid <= 2 {
        return true;
    }
    if let Ok(data) = fs::read_to_string(format!("/proc/{pid}/status")) {
        for line in data.lines() {
            if line.starts_with("Uid:") {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 2 {
                    return parts[1] == "0";
                }
            }
        }
    }
    false
}


#[derive(Serialize)]
struct RepairEntry {
    path: String,
    exists: bool,
    is_dir: bool,
    size_bytes: Option<u64>,
}

async fn repair_pack() -> Result<Response, Response> {
    let targets = vec![
        "/opt/saturn-go/bin/saturn-go",
        "/opt/saturn-go/scripts",
        "/opt/saturn-go/scripts/saturn-health-watchdog.sh",
        "/var/lib/saturn-state/repo_root.txt",
        "/var/lib/saturn-web/index.html",
        "/var/lib/saturn-web/backup.html",
        "/var/lib/saturn-web/monitor.html",
        "/var/lib/saturn-web/config.json",
        "/var/lib/saturn-web/themes.json",
        "/etc/systemd/system/saturn-go.service",
        "/etc/systemd/system/saturn-go-watchdog.service",
        "/etc/systemd/system/saturn-go-watchdog.timer",
        "/etc/nginx/sites-available/saturn",
        "/etc/nginx/conf.d/saturn_sse_map.conf",
        "/etc/nginx/.htpasswd",
    ];

    let mut entries: Vec<RepairEntry> = Vec::new();
    for p in &targets {
        let meta = fs::metadata(p).ok();
        let exists = meta.is_some();
        let is_dir = meta.as_ref().map(|m| m.is_dir()).unwrap_or(false);
        let size_bytes = meta.as_ref().and_then(|m| if m.is_file() { Some(m.len()) } else { None });
        entries.push(RepairEntry {
            path: p.to_string(),
            exists,
            is_dir,
            size_bytes,
        });
    }

    let ts = Local::now().format("%Y%m%d-%H%M%S").to_string();
    let temp_dir = PathBuf::from(format!("/tmp/saturn-repair-{ts}-{}", std::process::id()));
    tokio::fs::create_dir_all(&temp_dir)
        .await
        .map_err(|e| json_error(StatusCode::INTERNAL_SERVER_ERROR, &e.to_string()))?;

    let manifest_path = temp_dir.join("manifest.json");
    let manifest = serde_json::json!({
        "created": ts,
        "entries": entries,
    });
    tokio::fs::write(&manifest_path, serde_json::to_vec_pretty(&manifest).unwrap_or_default())
        .await
        .map_err(|e| json_error(StatusCode::INTERNAL_SERVER_ERROR, &e.to_string()))?;

    let mut cmd = Command::new("tar");
    cmd.arg("-czf")
        .arg("-")
        .arg("--absolute-names")
        .arg("--ignore-failed-read")
        .arg(manifest_path.to_string_lossy().to_string());

    for p in &targets {
        cmd.arg(p);
    }

    cmd.stdout(std::process::Stdio::piped());
    cmd.stderr(std::process::Stdio::piped());

    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(e) => return Err(json_error(StatusCode::INTERNAL_SERVER_ERROR, &e.to_string())),
    };

    let stdout = match child.stdout.take() {
        Some(s) => s,
        None => return Err(json_error(StatusCode::INTERNAL_SERVER_ERROR, "tar stdout missing")),
    };
    let stderr = child.stderr.take();
    let temp_dir2 = temp_dir.clone();

    tokio::spawn(async move {
        if let Some(err) = stderr {
            let mut lines = BufReader::new(err).lines();
            while let Ok(Some(line)) = lines.next_line().await {
                error!("tar stderr: {line}");
            }
        }
        let _ = child.wait().await;
        let _ = tokio::fs::remove_dir_all(&temp_dir2).await;
    });

    let stream = ReaderStream::new(stdout);
    let body = Body::from_stream(stream);

    let filename = format!("saturn-repair-pack-{ts}.tar.gz");
    let mut headers = HeaderMap::new();
    headers.insert("Content-Type", HeaderValue::from_static("application/gzip"));
    headers.insert(
        "Content-Disposition",
        HeaderValue::from_str(&format!("attachment; filename=\"{filename}\"")).unwrap_or_else(|_| {
            HeaderValue::from_static("attachment")
        }),
    );

    Ok((headers, body).into_response())
}

#[derive(Serialize)]
struct VerifyEntry {
    path: String,
    exists: bool,
}

async fn verify_system_config() -> impl IntoResponse {
    let required = vec![
        "/opt/saturn-go/bin/saturn-go",
        "/opt/saturn-go/scripts",
        "/opt/saturn-go/scripts/saturn-health-watchdog.sh",
        "/var/lib/saturn-state/repo_root.txt",
        "/var/lib/saturn-web/index.html",
        "/var/lib/saturn-web/backup.html",
        "/var/lib/saturn-web/monitor.html",
        "/var/lib/saturn-web/config.json",
        "/var/lib/saturn-web/themes.json",
        "/etc/systemd/system/saturn-go.service",
        "/etc/systemd/system/saturn-go-watchdog.service",
        "/etc/systemd/system/saturn-go-watchdog.timer",
        "/etc/nginx/sites-available/saturn",
        "/etc/nginx/conf.d/saturn_sse_map.conf",
        "/etc/nginx/.htpasswd",
    ];

    let mut missing: Vec<String> = Vec::new();
    let mut checks: Vec<VerifyEntry> = Vec::new();
    for p in &required {
        let exists = Path::new(p).exists();
        checks.push(VerifyEntry { path: p.to_string(), exists });
        if !exists {
            missing.push(p.to_string());
        }
    }

    let mut warnings: Vec<String> = Vec::new();
    if let Ok(cfg) = fs::read_to_string("/etc/nginx/sites-available/saturn") {
        if !cfg.contains("location /saturn/") {
            warnings.push("nginx config missing location /saturn/".to_string());
        }
        if !cfg.contains("location = /saturn/run") {
            warnings.push("nginx config missing SSE location /saturn/run".to_string());
        }
    } else {
        warnings.push("nginx config not readable".to_string());
    }

    if let Ok(out) = Command::new("systemctl").arg("is-active").arg("saturn-go.service").output().await {
        let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
        if s != "active" {
            warnings.push(format!("saturn-go.service not active ({s})"));
        }
    } else {
        warnings.push("systemctl is-active check failed".to_string());
    }

    if let Ok(out) = Command::new("systemctl")
        .arg("is-active")
        .arg("saturn-go-watchdog.timer")
        .output()
        .await
    {
        let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
        if s != "active" {
            warnings.push(format!("saturn-go-watchdog.timer not active ({s})"));
        }
    } else {
        warnings.push("systemctl watchdog timer check failed".to_string());
    }

    Json(serde_json::json!({
        "ok": missing.is_empty(),
        "missing": missing,
        "warnings": warnings,
        "checks": checks,
    }))
}
