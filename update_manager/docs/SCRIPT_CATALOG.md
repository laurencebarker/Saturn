# Script Catalog

This file documents the scripts deployed into `/opt/saturn-go/scripts` and related helper scripts currently in `update_manager/scripts`.

## Config-Driven Scripts (Shown in Main UI)

Defined in `config.json` and surfaced by `/get_scripts`.

| Script | Version | Purpose | Typical Flags |
|---|---|---|---|
| `update-G2.py` | `2.14` | Update Saturn repository and related components with backup options and privilege-aware behavior. | `--skip-git`, `-y`, `-n`, `--dry-run`, `--verbose` |
| `update-pihpsdr.py` | `1.10` | Update/build piHPSDR repository with backup options. | `--skip-git`, `-y`, `-n`, `--no-gpio`, `--dry-run`, `--verbose` |
| `log_cleaner.sh` | `3.00` | Find and optionally delete `*.log` files under home directory. | `--delete-all`, `--no-recursive`, `--dry-run` |
| `restore-backup.sh` | `3.10` | Restore Saturn or piHPSDR from backup directories with list/latest/explicit selection support. | `--saturn`, `--pihpsdr`, `--latest`, `--list`, `--backup-dir`, `--backup-name`, `--dry-run`, `--verbose`, `--json` |

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
- SSE streaming route (`/run`) handles stdout and stderr with low-latency buffering behavior.
