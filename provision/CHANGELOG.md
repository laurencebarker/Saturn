# Changelog

All notable changes to provisioning assets are documented in this file.

## [2026-02-15]

### Added

- Cloud-init provisioning script:
  - `cloud-init/provision-saturn.sh`
- Cloud-init example files:
  - `cloud-init/user-data.example.yaml`
  - `cloud-init/meta-data.example.yaml`
- Provisioning documentation:
  - `README.md`
  - `CHANGELOG.md`

### Changed

- Provisioning flow now includes repo-clean protections for Python:
  - disables repo bytecode writes with `PYTHONDONTWRITEBYTECODE=1`
  - uses `PYTHONPYCACHEPREFIX=/var/cache/saturn-python`
  - blocks Python script execution from repo tree during provisioning
  - cleans `__pycache__`, `*.pyc`, `*.pyo` from repo before completion
