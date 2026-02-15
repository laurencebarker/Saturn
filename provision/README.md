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

## Repo-Clean Safety Guard

Provisioning is configured to keep the repo clean of Python cache artifacts:

- `PYTHONDONTWRITEBYTECODE=1`
- `PYTHONPYCACHEPREFIX=/var/cache/saturn-python`
- blocks Python script execution from inside the repo tree during provisioning
- removes `__pycache__`, `*.pyc`, and `*.pyo` under repo before completion

## Notes

- Ensure `SATURN_USER` exists in the target image before provisioning runs.
- If you use a user other than `pi`, update `SATURN_USER` in `user-data`.
