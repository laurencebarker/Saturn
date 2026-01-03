#!/usr/bin/env bash
#
# update-p2app.sh
# --------------
# Build Saturn P2_app ("p2app") and optionally restart the systemd service.
#
# Design goals:
#  - Stop restart-storms first (stop/reset-failed)
#  - Run the Trixie/libgpiod v2 patch (via bash so exec-bit issues don't matter)
#  - Build cleanly
#  - Confirm binary exists before restarting
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
P2DIR_DEFAULT="${REPO_ROOT}/sw_projects/P2_app"

RESTART=0
DOPATCH=1
JOBS="$(nproc 2>/dev/null || echo 2)"
P2DIR="${P2DIR_DEFAULT}"

usage() {
  cat <<USAGE
Usage: update-p2app.sh [--restart] [--no-patch] [-j N] [--p2dir PATH]

Options:
  --restart        restart p2app systemd service after successful build
  --no-patch       skip scripts/patch-trixie-gpiod.sh
  -j, --jobs N     parallel build jobs (default: nproc)
  --p2dir PATH     override P2_app directory (default: ${P2DIR_DEFAULT})
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --restart) RESTART=1 ;;
    --no-patch) DOPATCH=0 ;;
    -j|--jobs) JOBS="${2:-}"; shift ;;
    --p2dir) P2DIR="${2:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

[[ -d "$P2DIR" ]] || { echo "P2_app dir not found: $P2DIR" >&2; exit 1; }
[[ -f "$P2DIR/Makefile" ]] || { echo "Makefile not found in: $P2DIR" >&2; exit 1; }

echo "Repo:  $REPO_ROOT"
echo "P2_app: $P2DIR"
echo "Jobs:  $JOBS"

# Stop service first so we don't get restart storms while the binary is missing
if systemctl list-unit-files | grep -q '^p2app\.service'; then
  sudo systemctl stop p2app || true
  sudo systemctl reset-failed p2app || true
fi

# Optional patch step (run via bash even if mode bits are wrong on someone’s clone)
if [[ "$DOPATCH" -eq 1 && -f "${REPO_ROOT}/scripts/patch-trixie-gpiod.sh" ]]; then
  echo "Running Trixie/libgpiod v2 patch..."
  bash "${REPO_ROOT}/scripts/patch-trixie-gpiod.sh"
fi

# Backup current binary if present
ts="$(date +%Y%m%d-%H%M%S)"
if [[ -x "$P2DIR/p2app" ]]; then
  cp -a "$P2DIR/p2app" "$P2DIR/p2app.prev.$ts"
  echo "Backed up existing p2app -> p2app.prev.$ts"
fi

echo "Building..."
make -C "$P2DIR" clean
make -C "$P2DIR" -j"$JOBS"

# Verify build produced the binary
if [[ ! -x "$P2DIR/p2app" ]]; then
  echo "ERROR: build did not produce executable: $P2DIR/p2app" >&2
  exit 1
fi

ls -l "$P2DIR/p2app"

# Restart if requested
if [[ "$RESTART" -eq 1 ]]; then
  sudo systemctl start p2app
  sudo systemctl status p2app --no-pager || true
fi

echo "Done."
