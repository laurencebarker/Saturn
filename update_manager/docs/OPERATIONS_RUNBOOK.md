# Operations Runbook

## Scope

This runbook covers day-2 operations for the Rust-based Saturn Update Manager deployment.

## Build and Install

### Build Backend Locally

```bash
cd /home/pi/github/Saturn/update_manager/rust-server
cargo check
cargo build --release
```

### Full Install (recommended)

```bash
cd /home/pi/github/Saturn
sudo bash update_manager/install_saturn_go_nginx.sh
```

Installer actions include:

- installs dependencies (`nginx`, `apache2-utils`, `rustc`, `cargo`, Python tools, etc.)
- builds and deploys Rust binary to `/opt/saturn-go/bin/saturn-go`
- copies web assets to `/var/lib/saturn-web`
- copies scripts to `/opt/saturn-go/scripts`
- grants service-user ownership of `/opt/saturn-go/scripts` so browser-managed custom script edits can persist
- writes NGINX config for `/saturn/*` and SSE route `/saturn/run`
- writes `saturn-go.service`, watchdog service, and watchdog timer
- waits for backend health at `/healthz`

## Update Existing Deployment

After pulling repo changes, run installer again:

```bash
cd /home/pi/github/Saturn
sudo bash update_manager/install_saturn_go_nginx.sh
```

Installer is designed to refresh service, web assets, scripts, and config.

## Uninstall

```bash
cd /home/pi/github/Saturn
sudo bash update_manager/uninstall_saturn_go_nginx.sh [--no-purge] [--keep-auth] [--remove-packages] [--dry-run] [--yes]
```

Default behavior purges runtime directories:

- `/opt/saturn-go`
- `/var/lib/saturn-web`
- `/var/lib/saturn-state`

## Service Operations

### Status and Logs

```bash
sudo systemctl status saturn-go.service
sudo journalctl -u saturn-go.service -n 200 --no-pager
sudo systemctl status saturn-go-watchdog.timer
```

### Restart

```bash
sudo systemctl restart saturn-go.service
sudo systemctl restart saturn-go-watchdog.timer
```

### NGINX Validation

```bash
sudo nginx -t
sudo systemctl reload nginx
```

### API Quick Checks

Through NGINX (authenticated session in browser) or locally against backend:

```bash
curl -fsS http://127.0.0.1:8080/healthz
curl -fsS http://127.0.0.1:8080/update_status
curl -fsS http://127.0.0.1:8080/list_repo_roots
curl -fsS "http://127.0.0.1:8080/run_log?script=update-G2.py&from=0&limit=20"
```

## Key Workflows

### Navigation Layout

- `/saturn/` opens G2 Update (default landing page).
- `/saturn/pihpsdr` opens dedicated piHPSDR update page.
- `/saturn/backup` opens Backup / Restore.
- `/saturn/custom` (and `/saturn/index`) opens Custom Scripts page.
- `/saturn/monitor` opens Monitor.
- Navigation order in current UI: `G2 Update` -> `piHPSDR Update` -> `Backup / Restore` -> `Custom Scripts` -> `Monitor`.

### Repo Root Management

- Use `backup.html` repo root controls, or call:

```bash
curl -sS -X POST http://127.0.0.1:8080/set_repo_root \
  -H 'Content-Type: application/json' \
  -H 'X-Saturn-CSRF: 1' \
  -d '{"repo_root":"/home/pi/github/Saturn"}'
```

Validation requires `.git` and `update_manager/` in the target path.

### Backup and Restore

- Download full backup from `backup.html` (or `GET /backup_full`).
- Validate archive first with restore dry-run (`POST /restore_full?dry_run=1`).
- Apply restore only after confirmation (`confirm=RESTORE`).
- For script-created directory backups, use Backup page "Script Backups" controls:
  - Saturn backups from `update-G2.py`: `GET /g2_backups`, `POST /g2_restore`
  - piHPSDR backups from `update-pihpsdr.py`: `GET /pihpsdr_backups`, `POST /pihpsdr_restore`

Important:

- restore overwrites active repo root using `rsync --delete`
- upload size is limited by `SATURN_RESTORE_MAX_UPLOAD_BYTES`
- non-dry-run full restore acquires the shared update lock; concurrent update actions return `409 Conflict`

### Appliance Update

1. Open G2 Update page (`/saturn/update`).
2. Enter GitHub repo URL and branch/ref.
3. Configure health-check URL and timeout.
4. Save settings (optional; Start also persists current values).
5. Start update.
6. Monitor `update_status` job until complete.
7. If needed, run rollback.

Current UI behavior:

- UI persists policy using `channel=custom` and `custom_ref=<branch/ref>`.
- Appliance policy panel stores repo/ref/health settings consumed by both transactional Appliance Update and `Run Update G2`.
- `Run Update G2` requires valid Appliance repo URL before run can start.
- `Run Update G2` auto-saves current Appliance settings before spawning script.
- Terminal output is resumable after tab/page changes using buffered `/run_log` polling.

G2 Update coordination notes:

- Update G2 terminal and Appliance Update now live on the same page.
- If Appliance Update already moved Git to target commit, run Update G2 with `--skip-git`.
- G2 runs and appliance update/rollback are mutually exclusive; overlapping requests return `409 Conflict`.

Update behavior:

- updates Git remote to expected GitHub URL from policy
- fetches target ref
- snapshots active repo (if enabled)
- stages update in `repo-staging` worktree
- switches active repo root only after staging
- health-check gates completion; failed checks auto-revert root

### Update G2 (Dedicated Terminal)

- Run `update-G2.py` from the G2 Update page to keep terminal output and Appliance Update state together.
- Repo URL in Appliance section must be valid before G2 run is enabled.
- Backend injects active repo-root environment for `/run`:
  - `SATURN_REPO_ROOT`
  - `SATURN_DIR`
  - `SATURN_ACTIVE_REPO_ROOT`
- This allows `update-G2.py` to target the active Saturn checkout without hardcoded path dependence.
- Output can be resumed from backend run logs (`/run_log`) after navigating away and back.

### Update piHPSDR (Dedicated Terminal)

- Run `update-pihpsdr.py` from `/saturn/pihpsdr`.
- This page mirrors the dedicated terminal workflow (flags + SSE output) used by Update G2.
- In non-interactive web execution, backup prompts are skipped unless `-y` is selected.
- Output can be resumed from backend run logs (`/run_log`) after navigating away and back.

### Custom Scripts (Browser Managed)

- Use `/saturn/custom` to add/update/delete custom script entries from browser.
- Optional script content can be written directly to scripts directory.
- Custom script metadata is persisted in `SATURN_CUSTOM_SCRIPTS_FILE`.
- Default custom scripts are seeded by backend startup:
  - `cleanup-saturn-logs.sh`
  - `cleanup-saturn-backups.sh`
- Custom script output also resumes through `/run_log` buffering.

### Backup and Restore Scope

- Backup / Restore page now focuses on:
  - repo-root selection
  - full backup/restore
  - repair pack and config verification
  - Pi image and removable-device clone workflows

### Password Change

`POST /change_password` updates `/etc/nginx/.htpasswd` for user `admin`.

If direct write is denied, backend retries with `sudo -n`. Ensure service user has sudoers permission for `htpasswd` if this route should work non-interactively.

### Monitor and Process Control

- `monitor.html` polls `/get_system_data` every 1 second.
- process kill button calls `POST /kill_process/:pid` with CSRF header.
- backend blocks protected/root-owned process targets.

## Environment Variables

Service environment commonly used in deployment:

- `SATURN_ADDR` (default `127.0.0.1:8080`)
- `SATURN_WEBROOT` (default `/var/lib/saturn-web`)
- `SATURN_CONFIG` (default `$SATURN_WEBROOT/config.json`)
- `SATURN_SCRIPTS_DIR` (default `/opt/saturn-go/scripts`)
- `SATURN_STATE_DIR` (default `/var/lib/saturn-state`)
- `SATURN_REPO_ROOT_FILE` (default `$SATURN_STATE_DIR/repo_root.txt`)
- `SATURN_UPDATE_POLICY_FILE` (default `$SATURN_STATE_DIR/update_policy.json`)
- `SATURN_UPDATE_STATE_FILE` (default `$SATURN_STATE_DIR/update_state.json`)
- `SATURN_SNAPSHOT_DIR` (default `$SATURN_STATE_DIR/snapshots`)
- `SATURN_STAGING_DIR` (default `$SATURN_STATE_DIR/repo-staging`)
- `SATURN_CUSTOM_SCRIPTS_FILE` (default `$SATURN_STATE_DIR/custom_scripts.json`)
- `SATURN_PIHPSDR_ROOT` (default `$HOME/github/pihpsdr`)
- `SATURN_FPGA_DIR` (optional override for FPGA image scan path)
- `SATURN_MAX_BODY_BYTES` (default `2147483648`)
- `SATURN_RESTORE_MAX_UPLOAD_BYTES` (default `2147483648`)
- `SATURN_NGINX_CLIENT_MAX_BODY_SIZE` (installer default `2G`)
- `SATURN_WATCHDOG_URL` (default `http://$SATURN_ADDR/healthz`)
- `SATURN_WATCHDOG_INTERVAL` (default `30s`)

## Troubleshooting

### UI Loads, API Calls Fail

1. Check backend service status/logs.
2. Confirm NGINX proxy config is valid.
3. Confirm backend bind address matches NGINX proxy target.

### Script Runs Show No Output or Slow Output

- verify script exists and is executable in `/opt/saturn-go/scripts`
- check service logs for spawn errors
- check NGINX still has dedicated `/saturn/run` SSE location
- verify buffered lines are available:

```bash
curl -sS "http://127.0.0.1:8080/run_log?script=update-G2.py&from=0&limit=50" | jq
```

### Restore Errors

Common causes:

- confirm token missing for non-dry-run restore
- archive too large for configured upload limit
- archive contains unsafe paths or unexpected top-level layout

### Appliance Update Errors

Common causes:

- invalid policy values (refs/owner/repo)
- remote fetch failures
- health check URL failure after staging
- insufficient disk space for snapshots/staging
- overlapping update actions (G2/appliance update/rollback) triggering `409 Conflict`

Check:

```bash
curl -sS http://127.0.0.1:8080/update_status | jq
ls -lah /var/lib/saturn-state/snapshots
ls -lah /var/lib/saturn-state/repo-staging
```

### Verify Runtime File Set

```bash
curl -sS http://127.0.0.1:8080/verify_system_config | jq
```

### Export Repair Pack

```bash
curl -sS http://127.0.0.1:8080/repair_pack -o saturn-repair-pack.tar.gz
```
