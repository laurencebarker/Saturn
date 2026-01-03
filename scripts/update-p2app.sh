#!/usr/bin/env bash
#
# update-p2app.sh
# -------------
# Build (and optionally restart) Saturn P2_app ("p2app") on Raspberry Pi.
#
# Goals:
#   - Be safe: never leave you without a working p2app binary if a build fails.
#   - Be robust on Debian/RPi OS "Trixie" (libgpiod v2) by running the v2 patch.
#   - Self-heal common Makefile breakage ("missing separator" = spaces instead of TABs).
#
# Typical use:
#   ./scripts/update-p2app.sh --restart
#
set -euo pipefail

# --------------------------- UI helpers ---------------------------

ts() { date +"%Y-%m-%d %H:%M:%S"; }
log() { printf "[%s] %s\n" "$(ts)" "$*"; }
hr()  { printf "%s\n\n" "##############################################################"; }

die() {
  echo
  log "ERROR: $*"
  exit 1
}

on_err() {
  local lineno="$1"
  local cmd="$2"
  echo
  log "ERROR: command failed (line ${lineno}): ${cmd}"
  exit 1
}
trap 'on_err "$LINENO" "$BASH_COMMAND"' ERR

usage() {
  cat <<'USAGE'
Usage: update-p2app.sh [options]

Options:
  --restart           Restart the systemd p2app service after a successful build (if present)
  --no-restart        Do not restart (default)
  --no-patch          Skip gpiod-v2 patch step (not recommended on Trixie)
  --jobs N, -j N      Parallel build jobs (default: nproc)
  --p2dir PATH        Override P2_app directory (default: <repo>/sw_projects/P2_app)
  -h, --help          Show this help

Notes:
  - If a build fails, this script restores the previous p2app binary (if one existed).
  - If Makefile recipes use spaces instead of TABs, it will auto-fix and retry once.
USAGE
}

# --------------------------- locate repo --------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"

# --------------------------- args ---------------------------------

RESTART=0
NO_PATCH=0
JOBS="$(nproc 2>/dev/null || echo 1)"
P2DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --restart) RESTART=1 ;;
    --no-restart) RESTART=0 ;;
    --no-patch) NO_PATCH=1 ;;
    --jobs|-j)
      [[ $# -ge 2 ]] || die "--jobs requires a value"
      JOBS="$2"
      shift
      ;;
    --p2dir)
      [[ $# -ge 2 ]] || die "--p2dir requires a value"
      P2DIR="$2"
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
  shift
done

if [[ -z "${P2DIR}" ]]; then
  P2DIR="${REPO_ROOT}/sw_projects/P2_app"
fi

[[ -d "${P2DIR}" ]] || die "P2_app directory not found: ${P2DIR}"

hr
log "Making p2app"
log "Repo: ${REPO_ROOT}"
log "P2App directory: ${P2DIR}"
log "Jobs: ${JOBS}"
echo
hr

# ------------------------ detect libgpiod -------------------------

detect_gpiod_major() {
  local ver=""
  if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists libgpiod 2>/dev/null; then
    ver="$(pkg-config --modversion libgpiod 2>/dev/null || true)"
  elif command -v gpiodetect >/dev/null 2>&1; then
    ver="$(gpiodetect --version 2>/dev/null | awk '{print $NF}' || true)"
  fi

  if [[ -z "${ver}" ]]; then
    echo "0"
    return
  fi

  echo "${ver%%.*}"
}

GPIOD_MAJOR="$(detect_gpiod_major)"
log "Detected libgpiod major: ${GPIOD_MAJOR}"

# --------------------- Makefile "TAB fix" -------------------------

fix_makefile_tabs() {
  local mk="$1"
  [[ -f "$mk" ]] || return 0

  python3 - <<'PY' "$mk"
import re, sys
from pathlib import Path

p = Path(sys.argv[1])
s = p.read_text()

# Convert 8 leading spaces on non-empty lines into a single TAB.
s2 = re.sub(r'^( {8})(?=\S)', '\t', s, flags=re.M)

if s2 != s:
    p.write_text(s2)
PY
}

# --------------------- patch step (gpiod v2) -----------------------

run_gpiod_patch_if_needed() {
  local patch="${REPO_ROOT}/scripts/patch-trixie-gpiod.sh"
  if [[ "${NO_PATCH}" -eq 1 ]]; then
    log "Skipping gpiod patch (--no-patch set)"
    return 0
  fi

  if [[ "${GPIOD_MAJOR}" -ge 2 ]]; then
    hr
    log "libgpiod v2 detected → applying v2 compatibility patch before build"
    hr
    [[ -x "$patch" ]] || die "Patch script not found/executable: ${patch}"
    APP_DIR="${P2DIR}" bash "$patch"
    log "gpiod v2 patch completed"
    hr
  else
    log "libgpiod v1 (or unknown) → skipping v2 patch"
  fi
}

# --------------------- build step (safe) ---------------------------

build_with_make() {
  local dir="$1"
  local mk="${dir}/Makefile"

  [[ -f "$mk" ]] || return 1

  fix_makefile_tabs "$mk"

  local ts_tag
  ts_tag="$(date +%Y%m%d-%H%M%S)"
  local cur_bin="${dir}/p2app"
  local bak_bin=""
  if [[ -x "$cur_bin" ]]; then
    bak_bin="${dir}/p2app.prev.${ts_tag}"
    cp -a "$cur_bin" "$bak_bin"
    log "Backed up existing p2app → ${bak_bin}"
  fi

  log "Using Makefile in ${dir}"
  ( cd "$dir" && make clean )

  local build_log
  build_log="$(mktemp)"
  set +e
  ( cd "$dir" && make -j"${JOBS}" ) 2>&1 | tee "$build_log"
  local rc="${PIPESTATUS[0]}"
  set -e

  if [[ "$rc" -ne 0 ]]; then
    if grep -qi "missing separator" "$build_log"; then
      log "Detected 'missing separator' → fixing Makefile TABs and retrying once"
      fix_makefile_tabs "$mk"
      rm -f "$build_log"
      build_log="$(mktemp)"
      set +e
      ( cd "$dir" && make -j"${JOBS}" ) 2>&1 | tee "$build_log"
      rc="${PIPESTATUS[0]}"
      set -e
    fi
  fi

  rm -f "$build_log"

  if [[ "$rc" -ne 0 ]]; then
    if [[ -n "$bak_bin" && -f "$bak_bin" ]]; then
      log "Build failed → restoring previous p2app from ${bak_bin}"
      cp -a "$bak_bin" "$cur_bin"
    fi
    return "$rc"
  fi

  [[ -x "$cur_bin" ]] || die "Build claimed success, but ${cur_bin} is missing or not executable"
  log "OK: P2App built: ${cur_bin}"
  return 0
}

# ---------------------- service restart ----------------------------

restart_service_if_requested() {
  if [[ "${RESTART}" -ne 1 ]]; then
    return 0
  fi

  if systemctl list-unit-files --type=service 2>/dev/null | grep -q '^p2app\.service'; then
    log "Restarting systemd service: p2app"
    sudo systemctl restart p2app
    sudo systemctl status p2app --no-pager || true
  else
    log "p2app.service not found; skipping restart"
  fi
}

# ------------------------------- main ------------------------------

run_gpiod_patch_if_needed

if ! build_with_make "${P2DIR}"; then
  die "Build failed"
fi

restart_service_if_requested

log "Done."

chmod +x scripts/update-p2app.sh
