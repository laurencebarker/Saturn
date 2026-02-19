use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::sync::{Arc, RwLock};

pub const DEFAULT_MAX_BODY_BYTES: u64 = 2 * 1024 * 1024 * 1024;
pub const DEFAULT_RESTORE_MAX_UPLOAD_BYTES: u64 = 2 * 1024 * 1024 * 1024;
pub const DEFAULT_UPDATE_HEALTH_TIMEOUT_SECS: u64 = 8;
pub const DEFAULT_UPDATE_KEEP_SNAPSHOTS: usize = 5;
pub const DEFAULT_STAGE_WORKTREE_KEEP: usize = 6;
pub const CSRF_HEADER_NAME: &str = "x-saturn-csrf";
pub const CSRF_HEADER_VALUE: &str = "1";
pub const RUN_LOG_MAX_LINES: usize = 5000;
pub const RUN_LOG_FETCH_MAX_LINES: usize = 1000;
pub const MAX_COMPLETED_JOBS: usize = 20;
pub const DEFAULT_CUSTOM_SCRIPT_CLEAN_LOGS: &str =
    include_str!("../../scripts/cleanup-saturn-logs.sh");
pub const DEFAULT_CUSTOM_SCRIPT_CLEAN_BACKUPS: &str =
    include_str!("../../scripts/cleanup-saturn-backups.sh");

#[derive(Clone)]
pub struct AppState {
    pub webroot: PathBuf,
    pub config_path: PathBuf,
    pub custom_scripts_file: PathBuf,
    pub scripts_dir: PathBuf,
    pub saturn_addr: String,
    pub repo_root: Arc<RwLock<PathBuf>>,
    pub repo_root_file: PathBuf,
    pub update_policy_file: PathBuf,
    pub update_state_file: PathBuf,
    pub snapshot_dir: PathBuf,
    pub staging_dir: PathBuf,
    pub restore_max_upload_bytes: u64,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct CfgEntry {
    pub filename: String,
    pub name: Option<String>,
    pub description: Option<String>,
    pub directory: Option<String>,
    pub category: Option<String>,
    pub flags: Option<Vec<String>>,
    pub version: Option<String>,
}

#[derive(Clone)]
pub struct DefaultCustomScript {
    pub entry: CfgEntry,
    pub content: &'static str,
}

#[derive(Debug, Deserialize)]
pub struct FlagsQuery {
    pub script: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct RunLogQuery {
    pub script: Option<String>,
    pub from: Option<usize>,
    pub limit: Option<usize>,
}

#[derive(Deserialize)]
pub struct PiImageStatusQuery {
    pub job_id: String,
}
