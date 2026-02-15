# Saturn Update Manager (saturn-go)

Saturn Update Manager provides a web UI for Saturn maintenance tasks.
The current backend is implemented in Rust (Axum), while deployment paths and
service names still use `saturn-go` for compatibility with existing installs.

## Documentation Map

- Architecture and internal flow: `docs/ARCHITECTURE.md`
- Full feature inventory (what was added and where): `docs/FEATURE_MATRIX.md`
- Backend endpoint reference: `docs/API_REFERENCE.md`
- Script inventory and usage map: `docs/SCRIPT_CATALOG.md`
- Build/install/operate/troubleshoot runbook: `docs/OPERATIONS_RUNBOOK.md`
- Docs index: `docs/README.md`

## Features

- Web UI for script execution, update coordination, monitoring, and backup/restore workflows
- Server-Sent Events (SSE) script output streaming
- Backend run-log buffering endpoint (`/run_log`) so terminal output can resume after page switches
- Full repository backup download and restore with archive validation
- Script backup integration: list and restore `saturn-backup-*` and `pihpsdr-backup-*` directories from Backup / Restore page
- Runtime repo-root switching via API/UI (`/list_repo_roots`, `/set_repo_root`)
- G2 Update is the default landing page (`/`, `update.html`) with Appliance Update policy/start/rollback
- Appliance Update policy panel (right side on desktop, below G2 terminal on narrow screens) stores GitHub repo URL + branch/ref + health-check values used by both Appliance Update and Run Update G2
- Dedicated piHPSDR Update page (`pihpsdr.html`) for `update-pihpsdr.py` terminal execution
- Dedicated FPGA Flash page (`fpga.html`) for `flash_fpga.sh` using `load-FPGA` (`-b`, `-v`, `-f`) with explicit confirmation guard
- Dedicated Custom Scripts page (`custom.html` / `index.html`) to add/update/delete runnable scripts from browser with file upload + flag metadata
- Default browser-managed custom scripts are auto-seeded on startup:
  - `cleanup-saturn-logs.sh`
  - `cleanup-saturn-backups.sh`
- Dedicated Backup / Restore page (`backup.html`) for repo-root management, backup/restore, Pi imaging, clone, and repair tools
- Navigation/page names in current UI are: `G2 Update`, `piHPSDR Update`, `FPGA Flash`, `Backup / Restore`, `Custom Scripts`, `Monitor`
- Pi image creation workflow with progress, validation, cancel, and download
- SD-to-removable-device cloning workflow with progress and cancel
- Repair Pack download and system config verification tools
- Built-in monitor for CPU, memory, disk, network, and process data
- Basic auth via NGINX
- CSRF protection for mutating API calls (`X-Saturn-CSRF` + same-host Origin/Referer validation when present)
- Low-latency script streaming: line-buffered subprocess launch (`stdbuf` when available), `\r`/`\n` output boundary handling, anti-buffer SSE headers, plus in-memory run-log buffering for reconnect
- Appliance update workflow: transactional repo staging, pre-update snapshot, policy-driven channels (`stable`/`beta`/`custom`), and rollback endpoint
- Shared update-activity lock prevents overlapping `update-G2` runs with appliance update/rollback operations
- Script runner injects active repo-root environment (`SATURN_REPO_ROOT`, `SATURN_DIR`, `SATURN_ACTIVE_REPO_ROOT`) so update scripts target the same checkout as backend state
- Health watchdog timer for self-heal restart if `/healthz` fails
- Repo-root safety checks for manual root switching and restore operations

## Runtime Layout

Typical deployed paths:

```text
/opt/saturn-go/
  bin/saturn-go                 # Rust server binary (legacy name retained)
  scripts/                      # runnable shell/python scripts

/var/lib/saturn-web/
  index.html
  update.html
  pihpsdr.html
  fpga.html
  monitor.html
  backup.html
  config.json
  themes.json

/var/lib/saturn-state/
  repo_root.txt
  custom_scripts.json
  update_policy.json
  update_state.json
  snapshots/
  repo-staging/
```

Repository source paths:

```text
update_manager/rust-server/     # Rust API server source
update_manager/templates/        # HTML templates copied to web root
update_manager/scripts/          # script and UI config assets
```

## Script Metadata and Versions

Script definitions come from `config.json` plus browser-managed custom entries in `custom_scripts.json`.

- UI script list: `/get_scripts`
- Flag list: `/get_flags`
- Version list ("Show versions above"): `/get_versions`
- G2 Update page: `/update` (also `/update.html`)
- piHPSDR update page: `/pihpsdr` (also `/pihpsdr.html`)
- FPGA flash page: `/fpga` (also `/fpga.html`)
- Custom scripts page: `/custom` (also `/custom.html`, `/index.html`)
- Discover FPGA image candidates: `GET /get_fpga_images`
- Active repo root: `/get_repo_root`
- Discover repo roots: `/list_repo_roots`
- Switch active repo root: `POST /set_repo_root` with JSON `{ "repo_root": "/path/to/tree" }`
- Get appliance update policy: `GET /update_policy`
- Set appliance update policy: `POST /update_policy`
- Start transactional update: `POST /update_start` with JSON `{ "channel":"stable|beta|custom", "custom_ref":"..." }`
- Get update status + last state: `GET /update_status`
- Roll back to previous repo root: `POST /update_rollback`
- List Update G2 backups: `GET /g2_backups`
- Validate/restore Update G2 backup directory: `POST /g2_restore` with JSON `{ "backup_name":"saturn-backup-...", "dry_run":true|false, "confirm":"RESTORE" }`
- List piHPSDR backups: `GET /pihpsdr_backups`
- Validate/restore piHPSDR backup directory: `POST /pihpsdr_restore` with JSON `{ "backup_name":"pihpsdr-backup-...", "dry_run":true|false, "confirm":"RESTORE" }`
- List browser-managed custom scripts: `GET /custom_scripts`
- Add/update browser-managed custom script entry: `POST /custom_scripts`
- Delete browser-managed custom script entry: `POST /custom_scripts_delete`
- Fetch buffered run output for a script: `GET /run_log?script=<filename>&from=<offset>&limit=<n>`

For mutating API requests (`POST` routes), include header:

- `X-Saturn-CSRF: 1`

The backend also validates `Origin`/`Referer` host against request `Host` when those headers are present.

If a script entry does not define `version`, `/get_versions` now returns
`unknown` instead of a hard-coded default.

## Privilege Behavior

### Script execution (`update-G2.py`)

`update-G2.py` is designed to run from both terminal and web service contexts:

- In verbose mode, commands that require captured output still return output
  (fixes `Size: ?` and `Commit: ?` in status sections).
- APT packages are checked first; installs are only attempted for missing
  packages.
- Privileged steps use:
  - direct execution when already root
  - `sudo` when interactive TTY is available
  - `sudo -n` for non-interactive service execution
- Required privileged steps exit with a clear actionable message when
  elevation is unavailable.
- Optional privileged steps (currently udev rules install in web/non-TTY mode)
  are skipped with a warning instead of failing the whole run.
- When launched by `/run`, the backend sets `SATURN_REPO_ROOT`, `SATURN_DIR`,
  and `SATURN_ACTIVE_REPO_ROOT` to the current active repo root before spawning
  the script.
- `/run` refuses Python script execution when the resolved script path is inside
  the active repo tree; use installed scripts under `/opt/saturn-go/scripts`.
- Python script runs from `/run` set `PYTHONDONTWRITEBYTECODE=1` and
  `PYTHONPYCACHEPREFIX=/var/cache/saturn-python` to keep source trees clean.

### Change Password

`/change_password` updates `/etc/nginx/.htpasswd` for `admin`.

- First tries `htpasswd` directly
- Then retries with `sudo -n htpasswd` for service-mode deployments
- Returns explicit guidance when sudo permissions are missing

## Build and Deploy (Rust Server)

Build from the repository:

```bash
cd /home/pi/github/Saturn/update_manager/rust-server
cargo check
cargo build --release
```

Deploy binary:

```bash
sudo cp target/release/saturn-go /opt/saturn-go/bin/saturn-go
sudo systemctl restart saturn-go.service
```

## Installation

Installer (deploy paths, service, web assets, scripts):

```bash
cd /home/pi/github/Saturn
sudo bash update_manager/install_saturn_go_nginx.sh
```

Auth bootstrap:

- If `SATURN_ADMIN_PASSWORD` is set, installer uses it for `admin`
- Otherwise installer prompts for a password when run interactively
- In non-interactive mode, installer generates a random password and prints it once

Installer behavior (current):

- Deploys Rust backend only (no legacy Go source generation)
- Proxies all `/saturn/*` routes through NGINX to the Rust backend
- Creates/updates `saturn-go.service` using a non-root service user
- Enables `saturn-go-watchdog.timer` to auto-restart service when health check fails
- Applies systemd hardening defaults (restricted kernel/control-group access, syscall architecture/address-family restrictions)
- Leaves `NoNewPrivileges` disabled so controlled `sudo -n` paths (for example password update) can work when sudoers permits them
- Sets `/opt/saturn-go/scripts` ownership to the service user/group so browser-managed custom script content can be saved

## Uninstall

Uninstaller aligned to the current installer:

```bash
cd /home/pi/github/Saturn
sudo bash update_manager/uninstall_saturn_go_nginx.sh [--no-purge] [--keep-auth] [--remove-packages] [--dry-run] [--yes]
```

Flags:

- Default behavior purges `/opt/saturn-go`, `/var/lib/saturn-web`, and `/var/lib/saturn-state` for clean reinstall
- `--no-purge`: keep `/opt/saturn-go`, `/var/lib/saturn-web`, and `/var/lib/saturn-state`
- `--keep-auth`: keep `/etc/nginx/.htpasswd`
- `--remove-packages`: best-effort removal of install-time packages
- `--dry-run`: print actions without making changes
- `--yes`: non-interactive confirmation

Default URL:

- `http://<host>/saturn/`

## Environment Variables

- `SATURN_ADDR` (default `127.0.0.1:8080`)
- `SATURN_WEBROOT` (default `/var/lib/saturn-web`)
- `SATURN_CONFIG` (default `$SATURN_WEBROOT/config.json`)
- `SATURN_SCRIPTS_DIR` (default `/opt/saturn-go/scripts`)
- `SATURN_REPO_ROOT` (default `$HOME/github/Saturn`)
- `SATURN_STATE_DIR` (installer default `/var/lib/saturn-state`)
- `SATURN_REPO_ROOT_FILE` (default `$SATURN_STATE_DIR/repo_root.txt`)
- `SATURN_MAX_BODY_BYTES` (default `2147483648`)
- `SATURN_RESTORE_MAX_UPLOAD_BYTES` (default `2147483648`)
- `SATURN_UPDATE_POLICY_FILE` (default `$SATURN_STATE_DIR/update_policy.json`)
- `SATURN_UPDATE_STATE_FILE` (default `$SATURN_STATE_DIR/update_state.json`)
- `SATURN_SNAPSHOT_DIR` (default `$SATURN_STATE_DIR/snapshots`)
- `SATURN_STAGING_DIR` (default `$SATURN_STATE_DIR/repo-staging`)
- `SATURN_CUSTOM_SCRIPTS_FILE` (default `$SATURN_STATE_DIR/custom_scripts.json`)
- `SATURN_PIHPSDR_ROOT` (default `$HOME/github/pihpsdr`)
- `SATURN_NGINX_CLIENT_MAX_BODY_SIZE` (installer default `2G`)
- `SATURN_WATCHDOG_URL` (installer default `http://$SATURN_ADDR/healthz`)
- `SATURN_WATCHDOG_INTERVAL` (installer default `30s`)
- `SATURN_ADMIN_PASSWORD` (optional non-interactive initial admin password)
- `SATURN_SERVICE_USER` (installer override for service user)
- `SATURN_SERVICE_GROUP` (installer override for service group)

## Troubleshooting

- UI loads but script output fails:
  - Check `systemctl status saturn-go.service`
  - Verify script exists and is executable in `/opt/saturn-go/scripts`
- Change Password fails:
  - Ensure `htpasswd` exists and service user can update
    `/etc/nginx/.htpasswd` (directly or via allowed `sudo -n`)
- Versions panel is blank or `unknown`:
  - Verify `version` keys in `/var/lib/saturn-web/config.json`

## Credits

- Original Saturn Update Manager by Jerry DeLong, KD4YAL
- Saturn Update Manager Rust backend and UI workflow extensions in this repo
