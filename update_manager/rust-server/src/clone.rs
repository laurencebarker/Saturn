use axum::{
    extract::Query,
    http::StatusCode,
    response::{IntoResponse, Json, Response},
};
use chrono::Local;
use serde::{Deserialize, Serialize};
use std::fs;
use std::sync::{Mutex, OnceLock};
use tokio::io::AsyncBufReadExt;
use tokio::process::Command;

use crate::state::{PiImageStatusQuery, MAX_COMPLETED_JOBS};
use crate::util::json_error;

#[derive(Debug, Clone, Serialize)]
pub struct PiCloneJob {
    id: String,
    status: String,
    progress: u8,
    message: String,
    pid: Option<u32>,
    log: Vec<String>,
}

static PI_CLONE_JOBS: OnceLock<Mutex<std::collections::HashMap<String, PiCloneJob>>> =
    OnceLock::new();

fn clone_jobs_map() -> &'static Mutex<std::collections::HashMap<String, PiCloneJob>> {
    PI_CLONE_JOBS.get_or_init(|| Mutex::new(std::collections::HashMap::new()))
}

fn set_clone_job(job: PiCloneJob) {
    let mut map = clone_jobs_map().lock().unwrap();
    map.insert(job.id.clone(), job);
    prune_completed_clone_jobs(&mut map);
}

fn prune_completed_clone_jobs(map: &mut std::collections::HashMap<String, PiCloneJob>) {
    let completed: Vec<String> = map
        .iter()
        .filter(|(_, j)| j.status != "running")
        .map(|(id, _)| id.clone())
        .collect();
    if completed.len() > MAX_COMPLETED_JOBS {
        let excess = completed.len() - MAX_COMPLETED_JOBS;
        for id in completed.into_iter().take(excess) {
            map.remove(&id);
        }
    }
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

#[derive(Serialize)]
pub struct PiDeviceInfo {
    name: String,
    path: String,
    size_bytes: u64,
    model: String,
}

pub async fn pi_devices() -> impl IntoResponse {
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
pub struct PiCloneStartReq {
    target: String,
}

pub async fn pi_clone_start(
    axum::extract::Json(req): axum::extract::Json<PiCloneStartReq>,
) -> Response {
    let target = req.target;
    if !target.starts_with("/dev/") {
        return json_error(StatusCode::BAD_REQUEST, "target must be a /dev path");
    }
    if target == "/dev/mmcblk0" {
        return json_error(StatusCode::BAD_REQUEST, "target cannot be source device");
    }

    let name = target.trim_start_matches("/dev/");
    let removable_path = std::path::Path::new("/sys/block")
        .join(name)
        .join("removable");
    let removable = fs::read_to_string(&removable_path)
        .ok()
        .map(|s| s.trim() == "1")
        .unwrap_or(false);
    if !removable {
        return json_error(StatusCode::BAD_REQUEST, "target device is not removable");
    }

    let id = format!(
        "piclone-{}-{}",
        std::process::id(),
        Local::now().format("%Y%m%d%H%M%S")
    );
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
                let mut lines = tokio::io::BufReader::new(out).lines();
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
                let mut lines = tokio::io::BufReader::new(err).lines();
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

pub async fn pi_clone_status(Query(q): Query<PiImageStatusQuery>) -> impl IntoResponse {
    if let Some(job) = get_clone_job(&q.job_id) {
        Json(job).into_response()
    } else {
        json_error(StatusCode::NOT_FOUND, "job not found")
    }
}

pub async fn pi_clone_cancel(Query(q): Query<PiImageStatusQuery>) -> impl IntoResponse {
    let job = match get_clone_job(&q.job_id) {
        Some(j) => j,
        None => return json_error(StatusCode::NOT_FOUND, "job not found"),
    };
    if job.status != "running" {
        return json_error(StatusCode::BAD_REQUEST, "job not running");
    }
    if let Some(pid) = job.pid {
        let _ = Command::new("kill")
            .arg("-15")
            .arg(pid.to_string())
            .status()
            .await;
    }
    update_clone_job(&q.job_id, |j| {
        j.status = "cancelled".to_string();
        j.message = "cancelled".to_string();
        j.pid = None;
    });
    Json(serde_json::json!({ "status": "cancelled" })).into_response()
}
