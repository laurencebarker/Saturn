# API Reference

## Base Path and Auth

In production, NGINX exposes the backend under `/saturn/`.

- Browser/UI calls use relative paths like `./update_status`, which resolve under `/saturn/`.
- NGINX has a dedicated SSE mapping for `/saturn/run` to backend `/run`.
- Basic Auth is enforced by NGINX for `/saturn/*` routes.

Direct backend routes are shown below without the `/saturn` prefix.

## CSRF Requirements

All `POST` endpoints require header:

- `X-Saturn-CSRF: 1`

Backend also enforces same-host checks when `Origin` or `Referer` is present.

## Page Routes

| Route | Method | CSRF | Description |
|---|---|---|---|
| `/` | `GET` | No | Serve `update.html` (G2 Update landing page). |
| `/custom` | `GET` | No | Serve `index.html` (Custom Scripts page). |
| `/custom.html` | `GET` | No | Serve `index.html` (Custom Scripts page). |
| `/index` | `GET` | No | Serve `index.html` (Custom Scripts page). |
| `/index.html` | `GET` | No | Serve `index.html` (Custom Scripts page). |
| `/backup` | `GET` | No | Serve `backup.html`. |
| `/backup.html` | `GET` | No | Serve `backup.html`. |
| `/update` | `GET` | No | Serve `update.html` (G2 + Appliance Update page). |
| `/update.html` | `GET` | No | Serve `update.html` (G2 + Appliance Update page). |
| `/pihpsdr` | `GET` | No | Serve `pihpsdr.html` (piHPSDR update terminal). |
| `/pihpsdr.html` | `GET` | No | Serve `pihpsdr.html` (piHPSDR update terminal). |
| `/monitor` | `GET` | No | Serve `monitor.html`. |
| `/monitor.html` | `GET` | No | Serve `monitor.html`. |
| fallback mapped page paths | `GET` | No | Supports `/saturn`, `/saturn/custom`, `/saturn/backup`, `/saturn/update`, `/saturn/pihpsdr`, `/saturn/monitor`, etc. |

## Health and Metadata

| Route | Method | CSRF | Request | Success Response |
|---|---|---|---|---|
| `/healthz` | `GET` | No | none | `200 OK` |
| `/get_scripts` | `GET` | No | none | `{ "scripts": { "Category": [...] }, "warnings": [] }` |
| `/get_flags` | `GET` | No | `?script=<filename>` | `{ "flags": ["--flag", ...] }` |
| `/get_versions` | `GET` | No | none | `{ "versions": { "script": "version|unknown" } }` |
| `/custom_scripts` | `GET` | No | none | `{ "scripts": [ { "filename","name","description","flags",... }, ... ] }` (includes seeded default cleanup entries if present) |
| `/custom_scripts` | `POST` | Yes | JSON `{ "filename","name","description","flags","content" }` | `{ "status":"ok", "script": {...} }` |
| `/custom_scripts_delete` | `POST` | Yes | JSON `{ "filename", "delete_file": bool }` | `{ "status":"ok" }` |
| `/get_fpga_images` | `GET` | No | none | `{ "dir", "images", "checked", "warning" }` |

## Repo Root Management

| Route | Method | CSRF | Request | Success Response |
|---|---|---|---|---|
| `/get_repo_root` | `GET` | No | none | `{ "repo_root": "/path" }` |
| `/list_repo_roots` | `GET` | No | none | `{ "active": "/path", "repo_roots": ["/path1", ...] }` |
| `/set_repo_root` | `POST` | Yes | JSON `{ "repo_root": "/path" }` | `{ "status":"ok", "repo_root":"/canonical/path" }` |

Validation rules for `/set_repo_root`:

- target must be a directory
- must contain `.git`
- must contain `update_manager/`

## Appliance Update

| Route | Method | CSRF | Request | Success Response |
|---|---|---|---|---|
| `/update_policy` | `GET` | No | none | `{ "policy": { ... } }` |
| `/update_policy` | `POST` | Yes | full policy JSON | `{ "status":"ok", "policy": { ...normalized... } }` |
| `/update_start` | `POST` | Yes | JSON `{ "channel":"stable|beta|custom", "custom_ref": "..." }` | `{ "status":"started", "job_id":"upd-..." }` |
| `/update_status` | `GET` | No | none | `{ "job": {...}|null, "last_update": {...}|null }` |
| `/update_rollback` | `POST` | Yes | none | `{ "status":"rolled_back", "repo_root":"/path" }` |

Conflict behavior (`409`):

- `POST /update_start`
  - returns conflict when an appliance update is already running
  - also returns conflict when another update activity is active (for example `update-G2.py`)
- `POST /update_rollback`
  - returns conflict when an appliance update is already running
  - also returns conflict when another update activity is active

`update_policy` fields:

- `owner`, `repo`, `remote`
- `channel`, `stable_ref`, `beta_ref`, `custom_ref`
- `auto_snapshot`, `keep_snapshots`
- `healthcheck_url`, `healthcheck_timeout_secs`

Normalization rules:

- invalid owner/repo/remote/ref values are sanitized to safe defaults
- `keep_snapshots` is clamped to `1..50`
- `healthcheck_timeout_secs` is clamped to `2..30`

Current UI behavior notes (`update.html`):

- Appliance form is simplified to GitHub repo URL + branch/ref + healthcheck URL/timeout.
- UI saves policy using `channel=custom` and `custom_ref=<branch/ref>`.
- `Run Update G2` is gated by valid repo URL in Appliance form and persists that policy before script start.

## Full Backup / Restore

| Route | Method | CSRF | Request | Success Response |
|---|---|---|---|---|
| `/backup_full` | `GET` | No | none | streaming `application/gzip` attachment |
| `/restore_full` | `POST` | Yes | `multipart/form-data` with `file`; optional `confirm=RESTORE`; optional query `dry_run=1|true|yes|y|on` | JSON status |
| `/g2_backups` | `GET` | No | none | `{ "home":"/home/...", "backups":[{ "name","path","files","dirs","bytes","modified_epoch" }, ...] }` |
| `/g2_restore` | `POST` | Yes | JSON `{ "backup_name":"saturn-backup-...", "dry_run":bool, "confirm":"RESTORE" }` | dry-run stats or `{ "status":"ok", ... }` |
| `/pihpsdr_backups` | `GET` | No | none | `{ "home":"/home/...", "backups":[{ "name","path","files","dirs","bytes","modified_epoch" }, ...] }` |
| `/pihpsdr_restore` | `POST` | Yes | JSON `{ "backup_name":"pihpsdr-backup-...", "dry_run":bool, "confirm":"RESTORE" }` | dry-run stats or `{ "status":"ok", ... }` |

Restore responses:

- dry-run: `{ "status":"ok", "dry_run":true, "files", "dirs", "bytes", ... }`
- apply: `{ "status":"ok" }`

Restore safety checks:

- upload size limit from `SATURN_RESTORE_MAX_UPLOAD_BYTES`
- tar path traversal guard (reject absolute and `..` paths)
- must extract to a single top-level directory
- uses `rsync -a --delete` into active repo root

`/g2_restore` safety checks:

- backup name must match `saturn-backup-*` and cannot include path traversal
- selected backup must resolve under backend `$HOME`
- selected backup and target repo root must both pass Saturn repo-root validation
- non-dry-run requires `confirm=RESTORE`
- non-dry-run acquires update-activity lock and returns `409` if conflicting update action is active

`/pihpsdr_restore` safety checks:

- backup name must match `pihpsdr-backup-*` and cannot include path traversal
- selected backup must resolve under backend `$HOME`
- selected backup and target piHPSDR root must both be valid git checkouts
- non-dry-run requires `confirm=RESTORE`
- non-dry-run acquires update-activity lock and returns `409` if conflicting update action is active

## Script Execution and Legacy Hooks

| Route | Method | CSRF | Request | Success Response |
|---|---|---|---|---|
| `/run` | `POST` | Yes | `multipart/form-data` with `script` + repeated `flags` | SSE stream (`text/event-stream`) |
| `/run_log` | `GET` | No | `?script=<filename>&from=<offset>&limit=<n>` | `{ "script","run_id","status","running","started_at","finished_at","from","next_from","total_lines","lines":[...] }` |
| `/backup_response` | `POST` | Yes | form payload from legacy prompt | `204 No Content` |
| `/exit` | `POST` | Yes | none | `{ "status":"shutting down" }` |

SSE output is streamed line-by-line, including stderr lines prefixed with `ERR:`.

Run-log buffering behavior:

- `/run` and `/run_log` share in-memory per-script run state.
- `run_log` supports resume via `from` offset and returns `next_from`.
- `run_log` returns `status` (`idle|running|done|error`) and current `run_id`.
- `run_log` max fetch `limit` is clamped by backend.

Update-activity behavior for `/run`:

- For `update-G2.py`/`update-G2.sh`, backend acquires the shared update-activity lock.
- If appliance update/rollback (or another G2 run) is active, route returns `409` with `{ "message": "..." }`.
- Child process environment includes:
  - `SATURN_REPO_ROOT`
  - `SATURN_DIR`
  - `SATURN_ACTIVE_REPO_ROOT`

## Credentials

| Route | Method | CSRF | Request | Success Response |
|---|---|---|---|---|
| `/change_password` | `POST` | Yes | `application/x-www-form-urlencoded`, `new_password=<value>` | `{ "status":"success" }` or `{ "status":"error", "message":"..." }` |

Behavior:

- enforces minimum length 5
- tries direct `htpasswd -i`
- retries with `sudo -n htpasswd -i` for service deployments

## Pi Image Workflow

| Route | Method | CSRF | Request | Success Response |
|---|---|---|---|---|
| `/pi_image_start` | `POST` | Yes | JSON `{ "shrink":bool, "compress":bool, "out_dir":"/path" }` | `{ "job_id":"piimg-..." }` |
| `/pi_image_status` | `GET` | No | `?job_id=<id>` | job JSON (`running|done|error|cancelled`) |
| `/pi_image_cancel` | `POST` | Yes | `?job_id=<id>` | `{ "status":"cancelled" }` |
| `/pi_image_download` | `GET` | No | `?job_id=<id>` | binary file download |

`/pi_image_download` schedules best-effort cleanup of the image file after download starts.

## Clone SD to Removable Device

| Route | Method | CSRF | Request | Success Response |
|---|---|---|---|---|
| `/pi_devices` | `GET` | No | none | `{ "devices": [{ "name", "path", "size_bytes", "model" }, ...] }` |
| `/pi_clone_start` | `POST` | Yes | JSON `{ "target":"/dev/sdX" }` | `{ "job_id":"piclone-..." }` |
| `/pi_clone_status` | `GET` | No | `?job_id=<id>` | clone job JSON |
| `/pi_clone_cancel` | `POST` | Yes | `?job_id=<id>` | `{ "status":"cancelled" }` |

Target must be a removable `/dev/*` device and cannot be `/dev/mmcblk0`.

## Monitor and Diagnostics

| Route | Method | CSRF | Request | Success Response |
|---|---|---|---|---|
| `/get_system_data` | `GET` | No | optional query: `proc_sort`, `proc_order`, `proc_user`, `proc_regex`, `proc_top`, `proc_page`, `proc_page_size` | CPU/memory/swap/disk/network/load/uptime/temp/processes JSON |
| `/network_test` | `GET` | No | none | `{ "tx_bps", "rx_bps", "seconds" }` or `{ "error": "..." }` |
| `/kill_process/:pid` | `POST` | Yes | optional `?sig=term|kill` | `{ "message":"OK" }` or error JSON |

`/kill_process/:pid` safeguards:

- rejects `pid <= 0`
- rejects protected processes (PID <= 2 or root-owned)

## Repair and Verification

| Route | Method | CSRF | Request | Success Response |
|---|---|---|---|---|
| `/repair_pack` | `GET` | No | none | streaming `tar.gz` repair bundle with manifest |
| `/verify_system_config` | `GET` | No | none | `{ "ok":bool, "missing":[], "warnings":[], "checks":[] }` |

## Common Error Format

Most error responses use:

```json
{ "message": "..." }
```

Some endpoints also return route-specific payloads such as `status` or `error` fields.
