# Saturn Update Manager Documentation

This folder contains the operational and technical documentation for the Rust-based Saturn Update Manager (`saturn-go`).

## Read This First

1. `ARCHITECTURE.md`
2. `FEATURE_MATRIX.md`
3. `API_REFERENCE.md`
4. `SCRIPT_CATALOG.md`
5. `OPERATIONS_RUNBOOK.md`

## Document Guide

- `ARCHITECTURE.md`
  - How requests flow through NGINX, the Rust API, scripts, and system services.
  - Runtime paths, persisted state, and security model.

- `FEATURE_MATRIX.md`
  - One place that maps each major feature to UI page, API endpoints, scripts, and state files.

- `API_REFERENCE.md`
  - Endpoint-by-endpoint reference for the backend API.
  - CSRF requirements, request format, and response notes.

- `SCRIPT_CATALOG.md`
  - Inventory of deployed scripts, versions, flags, and which API/UI path calls each one.

- `OPERATIONS_RUNBOOK.md`
  - Build, install, uninstall, daily operations, and troubleshooting.
  - Includes Update Center (G2 + Appliance Update) flow, backup/restore flow, and service checks.
