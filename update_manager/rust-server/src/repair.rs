use axum::{
    body::Body,
    http::{HeaderMap, HeaderValue, StatusCode},
    response::{IntoResponse, Json, Response},
};
use chrono::Local;
use serde::Serialize;
use std::fs;
use std::path::{Path, PathBuf};
use tokio::io::AsyncBufReadExt;
use tokio::process::Command;
use tokio_util::io::ReaderStream;
use tracing::error;

use crate::util::json_error;

#[derive(Serialize)]
struct RepairEntry {
    path: String,
    exists: bool,
    is_dir: bool,
    size_bytes: Option<u64>,
}

pub async fn repair_pack() -> Result<Response, Response> {
    let targets = vec![
        "/opt/saturn-go/bin/saturn-go",
        "/opt/saturn-go/scripts",
        "/usr/local/lib/saturn-go/saturn-health-watchdog.sh",
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
    ];

    let mut entries: Vec<RepairEntry> = Vec::new();
    for p in &targets {
        let meta = fs::metadata(p).ok();
        let exists = meta.is_some();
        let is_dir = meta.as_ref().map(|m| m.is_dir()).unwrap_or(false);
        let size_bytes = meta
            .as_ref()
            .and_then(|m| if m.is_file() { Some(m.len()) } else { None });
        entries.push(RepairEntry {
            path: p.to_string(),
            exists,
            is_dir,
            size_bytes,
        });
    }

    let ts = Local::now().format("%Y%m%d-%H%M%S").to_string();
    let temp_dir = PathBuf::from(format!(
        "/tmp/saturn-repair-{ts}-{}",
        std::process::id()
    ));
    tokio::fs::create_dir_all(&temp_dir)
        .await
        .map_err(|e| json_error(StatusCode::INTERNAL_SERVER_ERROR, &e.to_string()))?;

    let manifest_path = temp_dir.join("manifest.json");
    let manifest = serde_json::json!({
        "created": ts,
        "entries": entries,
    });
    tokio::fs::write(
        &manifest_path,
        serde_json::to_vec_pretty(&manifest).unwrap_or_default(),
    )
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
        Err(e) => {
            return Err(json_error(
                StatusCode::INTERNAL_SERVER_ERROR,
                &e.to_string(),
            ))
        }
    };

    let stdout = match child.stdout.take() {
        Some(s) => s,
        None => {
            return Err(json_error(
                StatusCode::INTERNAL_SERVER_ERROR,
                "tar stdout missing",
            ))
        }
    };
    let stderr = child.stderr.take();
    let temp_dir2 = temp_dir.clone();

    tokio::spawn(async move {
        if let Some(err) = stderr {
            let mut lines = tokio::io::BufReader::new(err).lines();
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
        HeaderValue::from_str(&format!("attachment; filename=\"{filename}\"")).unwrap_or_else(
            |_| HeaderValue::from_static("attachment"),
        ),
    );

    Ok((headers, body).into_response())
}

#[derive(Serialize)]
struct VerifyEntry {
    path: String,
    exists: bool,
}

pub async fn verify_system_config() -> impl IntoResponse {
    let required = vec![
        "/opt/saturn-go/bin/saturn-go",
        "/opt/saturn-go/scripts",
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
    let watchdog_candidates = vec![
        "/usr/local/lib/saturn-go/saturn-health-watchdog.sh",
        "/opt/saturn-go/scripts/saturn-health-watchdog.sh",
    ];

    let mut missing: Vec<String> = Vec::new();
    let mut checks: Vec<VerifyEntry> = Vec::new();
    for p in &required {
        let exists = Path::new(p).exists();
        checks.push(VerifyEntry {
            path: p.to_string(),
            exists,
        });
        if !exists {
            missing.push(p.to_string());
        }
    }
    let mut watchdog_exists = false;
    for p in &watchdog_candidates {
        let exists = Path::new(p).exists();
        checks.push(VerifyEntry {
            path: p.to_string(),
            exists,
        });
        watchdog_exists = watchdog_exists || exists;
    }
    if !watchdog_exists {
        missing.push(format!(
            "watchdog script missing (checked: {} | {})",
            watchdog_candidates[0], watchdog_candidates[1]
        ));
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

    if let Ok(out) = Command::new("systemctl")
        .arg("is-active")
        .arg("saturn-go.service")
        .output()
        .await
    {
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
