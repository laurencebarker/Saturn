use axum::{
    http::StatusCode,
    response::{IntoResponse, Json, Response},
};
use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};

use crate::state::AppState;

pub fn json_error(status: StatusCode, message: &str) -> Response {
    (status, Json(serde_json::json!({ "message": message }))).into_response()
}

pub fn output_error_text(output: &std::process::Output) -> String {
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

pub fn parse_boolish(v: Option<String>) -> bool {
    match v.as_deref() {
        Some("1") | Some("true") | Some("yes") | Some("y") | Some("on") => true,
        _ => false,
    }
}

pub fn is_safe_script_name(script: &str) -> bool {
    !script.is_empty() && !script.contains("..") && !script.contains('/') && !script.contains('\\')
}

pub fn is_safe_custom_script_filename(name: &str) -> bool {
    !name.is_empty()
        && !name.contains('/')
        && !name.contains('\\')
        && !name.contains("..")
        && name
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '_' || c == '-')
}

pub fn sanitize_custom_flags(flags: Option<Vec<String>>) -> Vec<String> {
    flags
        .unwrap_or_default()
        .into_iter()
        .map(|f| f.trim().to_string())
        .filter(|f| !f.is_empty())
        .filter(|f| !f.contains('\n') && !f.contains('\r') && !f.contains('\0'))
        .collect()
}

pub fn is_safe_backup_name_with_prefix(name: &str, prefix: &str) -> bool {
    !name.is_empty()
        && name.starts_with(prefix)
        && !name.contains('/')
        && !name.contains('\\')
        && !name.contains("..")
        && name
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_' || c == '.')
}

pub fn is_safe_repo_part(value: &str) -> bool {
    !value.is_empty()
        && value
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '_' || c == '-')
}

pub fn is_safe_ref_name(value: &str) -> bool {
    !value.is_empty()
        && !value.starts_with('-')
        && !value.contains("..")
        && value
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '/' || c == '.' || c == '_' || c == '-')
}

pub fn backup_home_dir() -> PathBuf {
    PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| "/home/pi".to_string()))
}

pub fn pihpsdr_repo_root() -> PathBuf {
    std::env::var("SATURN_PIHPSDR_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(|_| backup_home_dir().join("github").join("pihpsdr"))
}

pub fn validate_pihpsdr_repo_root(path: &Path) -> Result<(), String> {
    if !path.is_dir() {
        return Err("pihpsdr root is not a directory".to_string());
    }
    if !path.join(".git").exists() {
        return Err("pihpsdr root is not a git checkout".to_string());
    }
    Ok(())
}

pub fn current_repo_root(state: &AppState) -> PathBuf {
    state
        .repo_root
        .read()
        .unwrap_or_else(|e| e.into_inner())
        .clone()
}

pub fn is_saturn_repo_root(path: &Path) -> bool {
    path.is_dir() && path.join(".git").exists() && path.join("update_manager").is_dir()
}

pub fn validate_saturn_repo_root(path: &Path) -> Result<(), String> {
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

pub fn list_repo_root_candidates(active: &Path) -> Vec<String> {
    let mut set: BTreeSet<String> = BTreeSet::new();
    if is_saturn_repo_root(active) {
        set.insert(active.display().to_string());
    }

    if let Ok(home) = std::env::var("HOME") {
        for p in [
            PathBuf::from(&home).join("github/Saturn"),
            PathBuf::from(&home).join("github/saturn"),
        ] {
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
