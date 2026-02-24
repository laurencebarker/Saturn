# Saturn Provisioning

This directory contains provisioning assets for cloud-init based setup of a Saturn system.

## Current Layout

- `cloud-init/user-data.example.yaml`
- `cloud-init/meta-data.example.yaml`
- `cloud-init/provision-saturn.sh`

## What It Does

`cloud-init/provision-saturn.sh` runs as root and:

- installs required apt packages
- clones or updates `kd4yal2024/Saturn` (default branch `main`)
- builds Saturn apps and tools (including `sw_tools`)
- installs desktop launchers
- optionally builds/installs XDMA
- optionally installs udev rules
- optionally installs `p2app-control`
- optionally installs Update Manager
- optionally flashes FPGA (disabled by default)

Completion and logs:

- state file: `/var/lib/saturn-provision/complete`
- log file: `/var/log/saturn-provision.log`

## Raspberry Pi Imager Workflow (End-to-End)

This section describes the complete workflow for building an SD card with Raspberry Pi Imager and having Saturn provision automatically on first boot.

### 1. Choose an OS image that supports cloud-init

- This provisioning flow depends on cloud-init.
- Use an image that has cloud-init enabled (for example Ubuntu Server images in Raspberry Pi Imager, or a custom image where cloud-init is installed and active).
- If cloud-init is not active on the image, provisioning will not auto-run.

### 2. Prepare cloud-init inputs from this repo

From this repo:

- `provision/cloud-init/user-data.example.yaml`
- `provision/cloud-init/meta-data.example.yaml`

Copy and customize as needed:

- set `SATURN_USER` to the actual login user that will exist on the target image
- keep `SATURN_REPO_URL` and `SATURN_REPO_BRANCH` as needed
- review feature toggles (`SATURN_INSTALL_*`, `SATURN_REBUILD_XDMA`, `SATURN_BUILD_OPTIONAL_TOOLS`)
- leave FPGA flashing off by default unless intentionally enabled

### 3. Write SD card with Raspberry Pi Imager

- Select Raspberry Pi device
- Select OS image
- Select storage
- Open Imager OS customization and set hostname/user/SSH/network as needed
- Ensure the username configured in Imager matches `SATURN_USER` in `user-data`

### 4. Provide cloud-init seed files to the image

Depending on image behavior:

- If image + Imager path already supports cloud-init user-data injection, use that mechanism.
- Otherwise, after writing the card, mount the boot/system-boot partition and place files as:
  - `user-data`
  - `meta-data`
  using content from:
  - `provision/cloud-init/user-data.example.yaml`
  - `provision/cloud-init/meta-data.example.yaml`

### 5. First boot execution flow

On first boot, cloud-init processes `user-data` and executes:

- writes `/etc/default/saturn-provision`
- ensures `~/github/Saturn` exists for `SATURN_USER`
- clones or updates `kd4yal2024/Saturn`
- runs:
  - `bash "$SATURN_HOME/github/Saturn/provision/cloud-init/provision-saturn.sh"`

Then `provision-saturn.sh` performs:

- apt package install
- kernel header checks/install (for XDMA build path)
- Saturn repo sync and build of apps/tools
- desktop launcher install
- optional XDMA build/install/load
- optional udev rules install
- optional p2app-control install
- optional Update Manager install
- optional FPGA flash (only if explicitly enabled and confirmed)
- completion marker write

### 6. Verify completion

After boot completes, verify:

- `sudo cat /var/lib/saturn-provision/complete`
- `sudo tail -n 200 /var/log/saturn-provision.log`

If Update Manager is enabled, also verify service status:

- `sudo systemctl status saturn-go.service --no-pager`

### 7. Re-run behavior

- Provisioning is idempotent by state marker:
  - if `/var/lib/saturn-provision/complete` exists, script exits cleanly
- To force a full rerun, set:
  - `SATURN_FORCE_REPROVISION=1`
  in `/etc/default/saturn-provision`, then run the script again as root

## Cloud-Init Inputs

`cloud-init/user-data.example.yaml` writes `/etc/default/saturn-provision` and executes:

- `bash "$SATURN_HOME/github/Saturn/provision/cloud-init/provision-saturn.sh"`

`cloud-init/meta-data.example.yaml` is the companion metadata file for NoCloud style cloud-init.

## Important Defaults

From `user-data.example.yaml`:

- `SATURN_USER=pi`
- `SATURN_INSTALL_UPDATE_MANAGER=1`
- `SATURN_INSTALL_P2APP_CONTROL=1`
- `SATURN_INSTALL_UDEV_RULES=1`
- `SATURN_REBUILD_XDMA=1`
- `SATURN_BUILD_OPTIONAL_TOOLS=1`
- `SATURN_FLASH_FPGA=0` (safety default)

Important safety settings for flashing:

- `SATURN_FLASH_FPGA=0` keeps flashing disabled by default
- If set to `1`, `SATURN_FLASH_CONFIRM` is required
- Optional fallback flashing is controlled by `SATURN_FLASH_FALLBACK`

## Repo-Clean Safety Guard

Provisioning is configured to keep the repo clean of Python cache artifacts:

- `PYTHONDONTWRITEBYTECODE=1`
- `PYTHONPYCACHEPREFIX=/var/cache/saturn-python`
- blocks Python script execution from inside the repo tree during provisioning
- removes `__pycache__`, `*.pyc`, and `*.pyo` under repo before completion

## Notes

- Ensure `SATURN_USER` exists in the target image before provisioning runs.
- If you use a user other than `pi`, update `SATURN_USER` in `user-data`.
- Network access is required on first boot for apt and git operations.
