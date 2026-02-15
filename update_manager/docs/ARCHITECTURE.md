# Architecture

## System Overview

Saturn Update Manager is deployed as a small appliance-style web stack:

1. NGINX handles HTTP entry, Basic Auth, and reverse proxy.
2. Rust backend (`saturn-go`, Axum) serves pages and API endpoints.
3. Backend launches shell/Python scripts for maintenance tasks.
4. Systemd keeps the backend running and uses a watchdog timer for health-based restart.

## Request Flow

1. Browser requests `http://<host>/saturn/`.
2. NGINX enforces Basic Auth (`/etc/nginx/.htpasswd`).
3. NGINX proxies to Rust backend (`SATURN_ADDR`, default `127.0.0.1:8080`).
4. Backend returns HTML from `/var/lib/saturn-web` and JSON/SSE API responses.
5. For script execution, backend spawns scripts from `/opt/saturn-go/scripts` and streams output via SSE.

## UI Page Responsibilities

- `index.html`
  - Custom Scripts page (browser-managed script catalog + runner) and password change.
  - `update-G2.py`, `update-pihpsdr.py`, and `restore-backup.sh` are intentionally hidden from this page dropdown.
  - Supports browser file upload for custom script content and includes backend-seeded default custom cleanup scripts.
- `update.html`
  - Default landing page (`/`) that combines:
    - Update G2 terminal workflow (`POST /run` with `update-G2.py`)
    - Appliance Update policy/start/status/rollback controls (repo URL + branch/ref + healthcheck inputs in current UI).
    - G2 run button is gated by valid Appliance repo URL input.
- `pihpsdr.html`
  - Dedicated piHPSDR update terminal workflow (`POST /run` with `update-pihpsdr.py`).
- `fpga.html`
  - Dedicated FPGA flash workflow (`POST /run` with `flash_fpga.sh`) plus image discovery (`GET /get_fpga_images`).
- `backup.html`
  - Repo-root selection, full backup/restore, repair pack, Pi image workflow, and SD clone workflow.
- `monitor.html`
  - Real-time system monitoring and process controls.

## Runtime Layout

### Deployed Paths

- `/opt/saturn-go/bin/saturn-go`
  - Rust server binary.
- `/opt/saturn-go/scripts/`
  - Executable maintenance scripts (also target directory for browser-managed custom scripts).
- `/var/lib/saturn-web/`
  - Web assets: `index.html`, `update.html`, `pihpsdr.html`, `fpga.html`, `backup.html`, `monitor.html`, `config.json`, `themes.json`.
- `/var/lib/saturn-state/`
  - Mutable state: `repo_root.txt`, `update_policy.json`, `update_state.json`, snapshots, staged worktrees.
- `/etc/systemd/system/saturn-go.service`
  - Main backend service.
- `/etc/systemd/system/saturn-go-watchdog.service`
- `/etc/systemd/system/saturn-go-watchdog.timer`
  - Periodic health check and restart logic.
- `/etc/nginx/sites-available/saturn`
- `/etc/nginx/conf.d/saturn_sse_map.conf`
  - NGINX proxy config and SSE behavior.

### Source Paths

- `update_manager/rust-server/`
  - Rust backend source code.
- `update_manager/templates/`
  - UI templates copied to web root during install.
- `update_manager/scripts/`
  - Runtime scripts copied to `/opt/saturn-go/scripts`.

Browser-managed custom scripts:

- Metadata persisted at `SATURN_CUSTOM_SCRIPTS_FILE` (default `/var/lib/saturn-state/custom_scripts.json`).
- Optional script content writes to `SATURN_SCRIPTS_DIR` (default `/opt/saturn-go/scripts`).
- Backend seeds default custom entries (and missing files) on startup:
  - `cleanup-saturn-logs.sh`
  - `cleanup-saturn-backups.sh`

## Core State Model

- Active repo root is held in memory and persisted to `repo_root.txt`.
- Update policy is persisted in `update_policy.json`.
- Last successful update/rollback metadata is persisted in `update_state.json`.
- Snapshot archives are stored in `snapshots/`.
- Transactional update worktrees are stored in `repo-staging/`.
- A process-local update activity lock coordinates mutually exclusive update operations (appliance update, appliance rollback, and Update G2 runs).
- Process-local per-script run-log buffers (in memory) back `/run_log` resume behavior for terminal pages.

## Security Model

### Access Control

- External access is protected by NGINX Basic Auth.
- Backend is intended to bind loopback by default (`127.0.0.1:8080`).

### CSRF Protection

All mutating (`POST`) routes require:

- Header `X-Saturn-CSRF: 1`
- `Host` header present
- If `Origin` or `Referer` exists, its host must match request host

### Path/Target Safety

- Repo root switching and restore target must pass Saturn repo validation:
  - directory exists
  - `.git` exists
  - `update_manager/` exists
- Restore archive is rejected if any tar entry is absolute or includes `..`.
- Restore requires explicit `confirm=RESTORE` unless dry-run mode is used.
- Script runner rejects script names containing path traversal or separators.

## Transactional Appliance Update Flow

`POST /update_start` starts an async update job.

1. Load and normalize update policy.
2. Enforce expected remote URL (`https://github.com/<owner>/<repo>.git`) on configured remote name.
3. `git fetch --prune` on active repo.
4. Resolve target commit from selected channel (`stable`, `beta`, or `custom`).
5. If unchanged, mark job `no_change`.
6. Optional snapshot creation (`tar`) with retention pruning.
7. Create detached staged worktree in `repo-staging`.
8. Switch active repo root to staged worktree.
9. Run health check URL.
10. On failure: revert repo root and remove staged worktree.
11. On success: persist last update state and prune older staged worktrees.

Rollback (`POST /update_rollback`) re-points active repo root to `previous_repo_root` from last update state and re-runs health check.

Concurrency guard:

- Appliance update and rollback acquire the shared update-activity lock.
- If another update activity is already running, these routes return `409 Conflict`.

## Script Execution Model

- `POST /run` accepts multipart form:
  - `script=<filename>`
  - zero or more `flags=<flag>` values
- `GET /run_log` returns buffered output for a script by offset:
  - `?script=<filename>&from=<offset>&limit=<n>`
- Backend starts script from `SATURN_SCRIPTS_DIR` (default `/opt/saturn-go/scripts`).
- Output from stdout/stderr is streamed as SSE messages.
- Output is also copied into an in-memory per-script ring buffer so UI pages can resume output after tab/page switches.
- `stdbuf` + unbuffered Python mode are used when available to reduce output latency.
- Backend injects active repo-root context into child processes:
  - `SATURN_REPO_ROOT`
  - `SATURN_DIR`
  - `SATURN_ACTIVE_REPO_ROOT`
- For `update-G2.py`/`update-G2.sh`, `/run` also acquires the shared update-activity lock; conflicting update activity returns `409 Conflict`.

## Backup/Restore Model

- Full backup (`GET /backup_full`): streams a `tar.gz` of active repo root.
- Full restore (`POST /restore_full`): uploads archive to `/tmp`, validates and extracts it, then `rsync --delete` into active repo root.
- Dry-run restore (`?dry_run=1`) reports extracted tree stats without applying changes.
- Full restore requires extracted top-level directory to pass Saturn repo-root validation (`.git` + `update_manager/`).
- Non-dry-run full restore acquires the shared update-activity lock and returns `409 Conflict` if another update action is active.
- Update G2 directory backups (`GET /g2_backups`, `POST /g2_restore`): lists `saturn-backup-*` directories under backend `$HOME` and restores selected backup into active repo root with validation and confirm guard.
- piHPSDR directory backups (`GET /pihpsdr_backups`, `POST /pihpsdr_restore`): lists `pihpsdr-backup-*` directories under backend `$HOME` and restores selected backup into configured piHPSDR checkout.

## Monitor Model

- `GET /get_system_data` returns CPU, memory, swap, disk, network, load, uptime, temperature, and process list.
- `POST /kill_process/:pid` supports controlled process termination with safeguards for protected/root-owned processes.
- Monitor UI polls every 1 second for near-real-time display.
