use axum::{
    body::Body,
    extract::Query,
    http::{HeaderMap, HeaderValue, StatusCode},
    response::{IntoResponse, Json, Response},
};
use chrono::Local;
use serde::Serialize;
use std::path::Path;
use std::sync::{Mutex, OnceLock};
use std::time::Duration;
use tokio::io::AsyncBufReadExt;
use tokio::process::Command;
use tokio_util::io::ReaderStream;

use crate::state::{PiImageStatusQuery, MAX_COMPLETED_JOBS};
use crate::util::json_error;

#[derive(Debug, Clone, Serialize)]
pub struct PiImageJob {
    id: String,
    status: String,
    progress: u8,
    message: String,
    file_path: Option<String>,
    size_bytes: Option<u64>,
    sha256: Option<String>,
    pid: Option<u32>,
    log: Vec<String>,
}

static PI_IMAGE_JOBS: OnceLock<Mutex<std::collections::HashMap<String, PiImageJob>>> =
    OnceLock::new();

fn jobs_map() -> &'static Mutex<std::collections::HashMap<String, PiImageJob>> {
    PI_IMAGE_JOBS.get_or_init(|| Mutex::new(std::collections::HashMap::new()))
}

fn set_job(job: PiImageJob) {
    let mut map = jobs_map().lock().unwrap();
    map.insert(job.id.clone(), job);
    prune_completed_image_jobs(&mut map);
}

fn prune_completed_image_jobs(map: &mut std::collections::HashMap<String, PiImageJob>) {
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

#[derive(serde::Deserialize)]
pub struct PiImageStartReq {
    shrink: Option<bool>,
    compress: Option<bool>,
    out_dir: Option<String>,
}

pub async fn pi_image_start(
    axum::extract::Json(req): axum::extract::Json<PiImageStartReq>,
) -> Response {
    let shrink = req.shrink.unwrap_or(true);
    let compress = req.compress.unwrap_or(false);
    let out_dir = req.out_dir.unwrap_or_else(|| "/tmp".to_string());

    if !Path::new(&out_dir).is_dir() {
        return json_error(StatusCode::BAD_REQUEST, "out_dir is not a directory");
    }

    let id = format!(
        "piimg-{}-{}",
        std::process::id(),
        Local::now().format("%Y%m%d%H%M%S")
    );
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
                let mut lines = tokio::io::BufReader::new(out).lines();
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
                let mut lines = tokio::io::BufReader::new(err).lines();
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
                let path = get_job(&id).and_then(|j| j.file_path);
                if let Some(p) = path {
                    let size = tokio::fs::metadata(&p).await.ok().map(|m| m.len());
                    let sha = Command::new("sha256sum")
                        .arg(&p)
                        .output()
                        .await
                        .ok()
                        .and_then(|o| {
                            if o.status.success() {
                                let s = String::from_utf8_lossy(&o.stdout);
                                s.split_whitespace().next().map(|v| v.to_string())
                            } else {
                                None
                            }
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

pub async fn pi_image_status(Query(q): Query<PiImageStatusQuery>) -> impl IntoResponse {
    if let Some(job) = get_job(&q.job_id) {
        Json(job).into_response()
    } else {
        json_error(StatusCode::NOT_FOUND, "job not found")
    }
}

pub async fn pi_image_cancel(Query(q): Query<PiImageStatusQuery>) -> impl IntoResponse {
    let job = match get_job(&q.job_id) {
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
    update_job(&q.job_id, |j| {
        j.status = "cancelled".to_string();
        j.message = "cancelled".to_string();
        j.pid = None;
    });
    Json(serde_json::json!({ "status": "cancelled" })).into_response()
}

pub async fn pi_image_download(
    Query(q): Query<PiImageStatusQuery>,
) -> Result<Response, Response> {
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
    headers.insert(
        "Content-Type",
        HeaderValue::from_static("application/octet-stream"),
    );
    headers.insert(
        "Content-Disposition",
        HeaderValue::from_str(&format!("attachment; filename=\"{filename}\""))
            .unwrap_or_else(|_| HeaderValue::from_static("attachment")),
    );

    // best-effort cleanup after a delay long enough for large downloads
    tokio::spawn(async move {
        tokio::time::sleep(Duration::from_secs(600)).await;
        let _ = tokio::fs::remove_file(&path).await;
    });

    Ok((headers, body).into_response())
}
