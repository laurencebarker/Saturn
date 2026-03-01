# Changelog

All notable changes to the Saturn Update Manager (Rust) are documented here.

## [Unreleased]
### Added
- Graceful shutdown: server now handles SIGINT/SIGTERM via `axum::serve().with_graceful_shutdown()`, allowing in-flight requests to complete before exit.
- Runtime repo-tree discovery/switching API: `GET /list_repo_roots`, `POST /set_repo_root`, with persisted active root (`repo_root.txt`).
- Backup UI controls for selecting and applying the active repo root.
- Rust backend health endpoint: `GET /healthz`.
- CSRF request guard for mutating (`POST`) API routes using `X-Saturn-CSRF`, plus same-host Origin/Referer checks when present.
- Appliance update API: `GET/POST /update_policy`, `POST /update_start`, `GET /update_status`, `POST /update_rollback`.
- Transactional repo update flow with staged git worktree switch and rollback on health-check failure.
- Pre-update snapshot archives with retention policy in `/var/lib/saturn-state/snapshots`.
- Backup UI "Appliance Update" panel for channel policy, start/status, and rollback controls.
- `saturn-go-watchdog.timer` + `saturn-go-watchdog.service` for periodic health checks and self-heal restart.

### Changed
- CSRF middleware now rejects POST requests that are missing both `Origin` and `Referer` headers, closing a bypass when neither header was sent.
- `/get_system_data`: `proc_regex` query parameter now compiled with a 64 KB size limit via `RegexBuilder` to prevent regex-based CPU exhaustion.
- `/exit` endpoint now logs the remote IP at `warn` level before initiating shutdown.
- Pi image download cleanup delay increased from 30 seconds to 10 minutes, preventing file deletion while large downloads are still in progress.
- Completed Pi image and clone job maps are now pruned to a maximum of 20 entries, preventing unbounded memory growth over long uptimes.
- Default custom script constants replaced with `include_str!()` referencing `scripts/cleanup-saturn-logs.sh` and `scripts/cleanup-saturn-backups.sh`, eliminating source duplication.
- Updated `README.md` to document the current Rust/Axum backend, deployment layout, and compatibility naming (`saturn-go` service/binary).
- Documented version panel behavior and the non-interactive privilege model used by `update-G2.py` and `/change_password`.
- Replaced installer implementation with a Rust-only deployment flow (no embedded Go source generation/build).
- Installer now configures NGINX as a path-prefix reverse proxy for `/saturn/*` plus a dedicated SSE route for `/saturn/run`.
- Installer now enforces non-default admin bootstrap credentials (prompt/env/random generation), instead of shipping `admin/admin`.
- Re-aligned uninstall script to remove the exact artifacts created by current install flow (service, NGINX site, SSE map, optional auth/runtime purge).
- Uninstall now defaults to keeping runtime directories/custom state; use `--purge` for full cleanup.
- Installer script sync now preserves browser-managed custom scripts and only updates packaged scripts when source files are newer.
- Request body handling now uses explicit limits (`SATURN_MAX_BODY_BYTES`, `SATURN_RESTORE_MAX_UPLOAD_BYTES`) instead of unlimited bodies.
- Main, backup, and monitor web UIs now attach `X-Saturn-CSRF: 1` to all mutating API calls.
- `run` SSE path now streams with lower latency: line-buffered subprocess invocation (`stdbuf` when available), `\r` + `\n` boundary handling, and no-cache/anti-buffer response headers.
- NGINX `/saturn/run` now disables request buffering and adds explicit no-cache header to reduce end-to-end stream latency.
- Monitor refresh interval reduced from 3s to 1s for more appliance-like real-time visibility.
- Installer now writes update-policy/snapshot/staging env configuration into `saturn-go.service`.
- Installer now uses dedicated writable state path (`/var/lib/saturn-state`) for repo-root and appliance update state files.
- Installer now applies additional systemd hardening (`RestrictSUIDSGID`, `ProtectKernel*`, `ProtectControlGroups`, syscall/address-family restrictions).
- Installer now omits `NoNewPrivileges` in `saturn-go.service` so allowed `sudo -n` maintenance paths remain functional.
- Repo-root switching and restore now require Saturn-style git checkout paths (`.git` + `update_manager`), preventing destructive restore targets.
- Appliance update now prunes older staged worktrees under `/var/lib/saturn-state/repo-staging` to limit disk growth.
- Uninstaller now removes watchdog units and watchdog script to stay aligned with installer artifacts.
- `/run` now blocks Python script execution when the resolved script path is inside the active Saturn repo tree; only installed script copies are allowed.
- Python scripts launched by `/run` now set `PYTHONDONTWRITEBYTECODE=1` and `PYTHONPYCACHEPREFIX=/var/cache/saturn-python`.

### Fixed
- `update-G2.py`: verbose mode now preserves captured command output used by status sections (fixes `Size: ?` and `Commit: ?` cases).
- `update-G2.py`: library install now checks which APT packages are actually missing before attempting privileged installs.
- `update-G2.py`: privileged steps now use adaptive sudo behavior (`sudo` with TTY, `sudo -n` without TTY) with clearer failure messages.
- `/change_password`: backend now retries with `sudo -n htpasswd` and returns actionable permission errors when sudo rules are missing.
- `/get_versions`: missing script `version` metadata now returns `unknown` instead of a misleading hard-coded version.
- Added explicit `version` metadata for `update-G2.py` (`2.14`) and `update-pihpsdr.py` (`1.10`) in `scripts/config.json`.
- `/change_password`: switched to `htpasswd -i` with stdin input so passwords are not exposed in process arguments.
- `restore-backup.sh`: fixed `--list --json` runtime error and malformed JSON output.
- `restore-backup.sh`: added `--backup-name` support used by web UI restore flow.
- `monitor.html`: replaced process-row `innerHTML` injection with DOM `textContent` rendering for safer output handling.
- `scripts/config.json`: corrected restore script `directory` path metadata.
- Installer health check now fails loudly (with `systemctl`/`journalctl` diagnostics) if backend `/healthz` does not come up.
- Installer now always restarts `saturn-go.service` after writing the unit, preventing stale in-memory env (e.g., old bind port) on reinstall.
- Password minimum reduced to 5 characters across installer prompt, backend `/change_password`, and web UI validation.
- Light-theme terminal output now keeps compile/build lines readable (ANSI white mapped for light backgrounds), including the dedicated `pihpsdr.html` terminal view.
- `update-G2.py`: added an automatic CAT signature compatibility patch for `sw_projects/P2_app/g2panel_libgpiodv2.c` after pulls, fixing recent `MakeProductVersionCAT` build breaks.
- `update-G2.py`: `install_udev_rules` now skips with warning (instead of hard-failing the full update) in non-interactive mode when passwordless sudo is unavailable.
- G2 terminal runner now enforces a configured Appliance Update repo URL; if not configured, `/run` returns a clear error instead of silently using defaults.
- G2 terminal runner now passes Appliance Update policy repo/remote/ref into `update-G2.py`, and `update-G2.py` now applies that policy by setting the git remote URL before pulling.
- `update-G2.py` and `update-pihpsdr.py` now refuse execution when run from inside the Saturn repo tree, preventing accidental repo-local Python runs.

## [2026-02-13]
### Added
- Full repo backup download (`/backup_full`) and restore (`/restore_full`) with validation and RESTORE confirmation.
- Dedicated **Backup / Restore** page (`backup.html`) linked from the main UI.
- Pi image creation workflow with progress, validation (size + SHA256), and download cleanup.
- Output directory selection for Pi image creation (default `/mnt/usb`).
- Pi image cancel support and live log panel.
- Clone SD card to removable device workflow with auto-detected targets, progress, and cancel.
- Repair Pack download and system config verification tools.
- New script `clone_pi_to_device.sh`.

### Changed
- Disabled default request body limits to support large uploads.
- Removed **Create Pi Image** from the main script list (moved to backup page).
- Added `SATURN_REPO_ROOT` env var for configurable repo root.

### Fixed
- Restores now accept `dry_run=1` and similar boolean query values.
