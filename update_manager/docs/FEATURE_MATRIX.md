# Feature Matrix

This matrix maps current capabilities to the implementation points in UI, backend API, scripts, and persisted state.

| Capability | UI | API Endpoints | Scripts / Commands | State / Files |
|---|---|---|---|---|
| Browser-managed custom script runner with live output | `index.html` (`/custom`) | `POST /run`, `GET /run_log` | `/opt/saturn-go/scripts/*` launched by backend | `custom_scripts.json`, in-memory run-log buffer |
| Custom script catalog management (add/update/delete + upload) | `index.html` (`/custom`) | `GET/POST /custom_scripts`, `POST /custom_scripts_delete` | Optional script file write/remove in scripts dir | `custom_scripts.json`, `/opt/saturn-go/scripts` |
| Backend-seeded default custom maintenance scripts | `index.html` (`/custom`) | `GET /custom_scripts` | `cleanup-saturn-logs.sh`, `cleanup-saturn-backups.sh` | `custom_scripts.json`, `/opt/saturn-go/scripts` |
| Dedicated Update G2 terminal runner | `update.html` (requires valid Appliance repo URL in UI) | `POST /run`, `GET /run_log` (with `script=update-G2.py`) | `update-G2.py` | Process-local update-activity lock, in-memory run-log buffer |
| Dedicated piHPSDR terminal runner | `pihpsdr.html` | `POST /run`, `GET /run_log` (with `script=update-pihpsdr.py`) | `update-pihpsdr.py` | In-memory run-log buffer |
| Dedicated FPGA flash runner | `fpga.html` | `POST /run`, `GET /run_log` (with `script=flash_fpga.sh`), `GET /get_fpga_images` | `flash_fpga.sh` -> `sw_tools/load-FPGA/load-FPGA` | In-memory run-log buffer |
| Script catalog and flag metadata | `index.html`, `update.html`, `pihpsdr.html` | `GET /get_scripts`, `GET /get_flags`, `GET /get_versions` | Reads `config.json` | `/var/lib/saturn-web/config.json` |
| Repo root discovery and switch | `backup.html` | `GET /list_repo_roots`, `GET /get_repo_root`, `POST /set_repo_root` | Path validation in backend | `repo_root.txt` |
| Full repo backup download | `backup.html` | `GET /backup_full` | `tar -czf -` | Active repo root content |
| Full repo restore (validate/apply) | `backup.html` | `POST /restore_full` | `tar -tzf`, `tar -xzf`, `rsync -a --delete` (non-dry-run guarded by shared update lock) | Active repo root content |
| Restore from script-managed directory backups | `backup.html` | `GET /g2_backups`, `POST /g2_restore`, `GET /pihpsdr_backups`, `POST /pihpsdr_restore` | `rsync -a --delete` from selected `saturn-backup-*` or `pihpsdr-backup-*` dir | `~/saturn-backup-*`, `~/pihpsdr-backup-*` |
| Transactional appliance update | `update.html` (repo URL + branch/ref + health fields in UI) | `GET/POST /update_policy`, `POST /update_start`, `GET /update_status`, `POST /update_rollback` | `git fetch`, `git worktree add/remove`, `curl` health check, snapshot `tar` | `update_policy.json`, `update_state.json`, `snapshots/`, `repo-staging/` |
| Buffered terminal resume across page switches | `update.html`, `pihpsdr.html`, `index.html` | `GET /run_log` | Offset polling by script + run ID | In-memory per-script run log ring |
| Pre-update snapshots + retention | `update.html` status panel | Part of update workflow | `tar` snapshot + prune logic | `snapshots/` |
| G2/appliance mutual exclusion guard | `update.html` conflict feedback | `POST /run` (`update-G2.py` only), `POST /update_start`, `POST /update_rollback` | In-memory activity acquisition/release | Process-local lock slot |
| Pi image creation and validation | `backup.html` | `POST /pi_image_start`, `GET /pi_image_status`, `POST /pi_image_cancel`, `GET /pi_image_download` | `make_pi_image.sh`, `sha256sum` | In-memory job state; temporary image files |
| Clone SD card to removable device | `backup.html` | `GET /pi_devices`, `POST /pi_clone_start`, `GET /pi_clone_status`, `POST /pi_clone_cancel` | `clone_pi_to_device.sh` | In-memory clone job state |
| Repair pack export | `backup.html` | `GET /repair_pack` | `tar -czf -` over key runtime files | Generated manifest in `/tmp` |
| Runtime/config verification | `backup.html` | `GET /verify_system_config` | Filesystem checks + `systemctl is-active` | N/A |
| Password change in UI | `index.html` | `POST /change_password` | `htpasswd -i` (direct or `sudo -n`) | `/etc/nginx/.htpasswd` |
| Service self-health watchdog | Not directly in UI | `GET /healthz` consumed by watchdog | `/usr/local/lib/saturn-go/saturn-health-watchdog.sh`, systemd timer/service | `saturn-go-watchdog.*` units |
| System monitor dashboard | `monitor.html` | `GET /get_system_data`, `GET /network_test`, `POST /kill_process/:pid` | `/proc`, sysfs, `curl`, `kill` | N/A |
| FPGA image discovery for flash UI | `fpga.html` | `GET /get_fpga_images` | Directory scan for `.bin` files | `SATURN_FPGA_DIR` or repo paths |
| Legacy backup prompt response hook | `index.html` (modal) | `POST /backup_response` | No-op backend endpoint | N/A |
| Controlled backend shutdown | `index.html` Exit button | `POST /exit` | `std::process::exit(0)` | N/A |

## Added/Expanded Areas

Compared to a simple script-runner deployment, the following were added as first-class features:

- Backup and restore page with repo-root awareness
- Dedicated G2 Update page that pairs Update G2 terminal output with Appliance Update controls
- Dedicated FPGA Flash page for safe `load-FPGA` execution
- Transactional appliance update policy, execution, status, and rollback
- Pre-update snapshots and staging lifecycle management
- Shared update-activity lock to prevent overlapping G2/appliance update actions
- Pi image creation and removable-device clone workflows
- Repair pack generation and install verification tooling
- CSRF enforcement on all mutating routes
- Watchdog timer/service for automatic restart after failed health checks
- Enhanced monitor endpoint coverage with process actions and throughput metrics
