use axum::{
    extract::Query,
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Json},
};
use serde::Deserialize;
use std::time::Duration;
use tokio::io::AsyncWriteExt;
use tokio::process::Command;

use crate::util::{json_error, output_error_text};

#[derive(Deserialize)]
pub struct PasswordForm {
    new_password: String,
}

async fn run_htpasswd(
    new_password: &str,
    use_sudo: bool,
) -> Result<std::process::Output, std::io::Error> {
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

pub async fn change_password(
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

pub async fn exit_server(headers: HeaderMap) -> impl IntoResponse {
    let remote = headers
        .get("x-forwarded-for")
        .or_else(|| headers.get("x-real-ip"))
        .and_then(|v| v.to_str().ok())
        .unwrap_or("unknown");
    tracing::warn!("exit_server called (remote: {remote}); shutting down in 200ms");
    tokio::spawn(async {
        tokio::time::sleep(Duration::from_millis(200)).await;
        std::process::exit(0);
    });
    Json(serde_json::json!({ "status":"shutting down" }))
}

#[derive(Deserialize)]
pub struct KillQuery {
    sig: Option<String>, // term|kill
}

pub async fn kill_process(
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

fn is_protected_pid(pid: i32) -> bool {
    if pid <= 2 {
        return true;
    }
    if let Ok(data) = std::fs::read_to_string(format!("/proc/{pid}/status")) {
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
