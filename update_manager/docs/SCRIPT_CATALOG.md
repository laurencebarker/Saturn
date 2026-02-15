# Script Catalog

This file documents the scripts deployed into `/opt/saturn-go/scripts` and related helper scripts currently in `update_manager/scripts`.

## Config-Driven Scripts (Exposed by API)

Defined in `config.json` and surfaced by `/get_scripts`.

| Script | Version | Purpose | Typical Flags |
|---|---|---|---|
| `update-G2.py` | `2.14` | Update Saturn repository and related components with backup options and privilege-aware behavior. | `--skip-git`, `-y`, `-n`, `--dry-run`, `--verbose` |
| `update-pihpsdr.py` | `1.10` | Update/build piHPSDR repository with backup options. | `--skip-git`, `-y`, `-n`, `--no-gpio`, `--dry-run`, `--verbose` |
| `log_cleaner.sh` | `3.00` | Find and optionally delete `*.log` files under home directory. | `--delete-all`, `--no-recursive`, `--dry-run` |
| `restore-backup.sh` | `3.10` | Restore Saturn or piHPSDR from backup directories with list/latest/explicit selection support. | `--saturn`, `--pihpsdr`, `--latest`, `--list`, `--backup-dir`, `--backup-name`, `--dry-run`, `--verbose`, `--json` |

UI usage notes:

- `index.html` (Custom Scripts page) intentionally excludes `update-G2.py` from the dropdown.
- `update.html` (G2 Update page) is the dedicated UI for running `update-G2.py` with live SSE terminal output.
- `index.html` (Custom Scripts page) intentionally excludes `update-pihpsdr.py` from the dropdown.
- `pihpsdr.html` is the dedicated UI for running `update-pihpsdr.py` with live SSE terminal output.
- `restore-backup.sh` is intentionally excluded from the main dropdown; Backup / Restore page provides dedicated restore controls for script-created backup directories.
- `index.html` is used as the browser-managed Custom Scripts page (`/custom`), backed by `custom_scripts.json`.
- `/run` executes scripts from `/opt/saturn-go/scripts`.
- `/run_log` provides buffered per-script run output by offset (used for resume after page switches).

## Backend-Seeded Default Custom Scripts

These are created/registered by backend startup when missing and appear in `/custom_scripts`.

| Script | Purpose | Typical Flags |
|---|---|---|
| `cleanup-saturn-logs.sh` | Remove Saturn update log files in `~/saturn-logs` (retention-oriented by default). | `--all`, `--older-7`, `--dry-run`, `--verbose` |
| `cleanup-saturn-backups.sh` | Prune `~/saturn-backup-*` and `~/pihpsdr-backup-*` directories (keeps newest 2 by default). | `--saturn-only`, `--pihpsdr-only`, `--delete-all`, `--dry-run`, `--verbose` |

## Backup Page Workflows

These are invoked by dedicated backup-page API routes.

| Script | Trigger Route(s) | Purpose |
|---|---|---|
| `make_pi_image.sh` | `/pi_image_start` (+ status/cancel/download routes) | Create SD image from `/dev/mmcblk0`, optional shrink/compress, return file for download. |
| `clone_pi_to_device.sh` | `/pi_clone_start` (+ status/cancel routes) | Clone `/dev/mmcblk0` to selected removable target device. |

## Additional Utilities in Repo

Not all utilities are directly wired into current UI buttons, but are included in the managed script set.

| Script | Purpose | Key Flags |
|---|---|---|
| `flash_fpga.sh` | Flash selected FPGA image to primary/fallback offset using `spiload` with confirmation guard. | `--image`, `--latest`, `--primary`, `--fallback`, `--confirm`, `--dry-run` |
| `qemu_pi_boot.sh` | Boot Raspberry Pi image in QEMU by extracting kernel/DTB and launching `qemu-system-aarch64`. | `--img`, `--work-dir`, `--memory`, `--cpus`, `--machine`, `--extra-append`, `--dry-run` |
| `log_cleaner.sh` | Local log cleanup helper. | see above |

## Operational Notes

- Scripts are copied from `update_manager/scripts` during install.
- File permissions are normalized by installer:
  - `*.sh` and `*.py` scripts are set executable.
- Script execution from UI is constrained to filenames in `/opt/saturn-go/scripts`.
- Installer permissions keep `/opt/saturn-go/scripts` writable by the service user so browser-managed custom script content updates can persist.
- SSE streaming route (`/run`) handles stdout and stderr with low-latency buffering behavior.
- `/run` injects active repo-root context (`SATURN_REPO_ROOT`, `SATURN_DIR`, `SATURN_ACTIVE_REPO_ROOT`) so scripts operate on the currently selected Saturn checkout.
- `update-G2.py` participates in the shared update-activity lock with appliance update/rollback routes to avoid overlapping update operations.
