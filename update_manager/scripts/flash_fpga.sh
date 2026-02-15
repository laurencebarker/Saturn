#!/usr/bin/env bash
set -euo pipefail

# flash_fpga.sh - Safe FPGA flashing helper for Saturn
# Version: 1.0.0
#
# Requirements:
# - Must run on Raspberry Pi (not WSL/desktop)
# - Uses sw_tools/spiload with explicit offsets
# - Verification is always enabled
#
# Offsets:
#   Primary image:  9961472
#   Fallback image: 0

PRIMARY_OFFSET="9961472"
FALLBACK_OFFSET="0"

IMAGE=""
USE_FALLBACK=false
USE_PRIMARY=false
CONFIRM=""
DRY_RUN=false

progress(){ echo "Progress: $1%"; }
info(){ echo "$@"; }
warn(){ echo "WARN: $@"; }
err(){ echo "ERR: $@" >&2; exit 1; }
run_as_root(){
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo -n "$@"
  fi
}

discover_user_home(){
  local home_guess="$HOME"
  if [[ "$(id -u)" -eq 0 && -n "${SUDO_USER:-}" ]]; then
    local sudo_home
    sudo_home="$(getent passwd "$SUDO_USER" | cut -d: -f6 || true)"
    if [[ -n "$sudo_home" ]]; then
      home_guess="$sudo_home"
    fi
  fi
  echo "$home_guess"
}

resolve_saturn_dir(){
  local user_home="$1"
  local candidates=()

  if [[ -n "${SATURN_DIR:-}" ]]; then
    candidates+=("$SATURN_DIR")
  fi
  if [[ -n "${SATURN_FPGA_DIR:-}" ]]; then
    candidates+=("$(dirname "$SATURN_FPGA_DIR")")
  fi
  candidates+=("$user_home/github/Saturn" "$user_home/github/saturn")
  if [[ -n "${SUDO_USER:-}" ]]; then
    candidates+=("/home/$SUDO_USER/github/Saturn" "/home/$SUDO_USER/github/saturn")
  fi

  local c
  for c in "${candidates[@]}"; do
    if [[ -d "$c/sw_tools" ]]; then
      echo "$c"
      return 0
    fi
  done
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image)
      [[ $# -ge 2 ]] || err "--image requires a path"
      IMAGE="$2"
      shift 2
      ;;
    --latest)
      IMAGE="latest"
      shift
      ;;
    --primary)
      USE_PRIMARY=true
      shift
      ;;
    --fallback)
      USE_FALLBACK=true
      shift
      ;;
    --confirm)
      [[ $# -ge 2 ]] || err "--confirm requires a value"
      CONFIRM="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    *) err "Unknown argument: $1" ;;
  esac
done

progress 5

if [[ -f /proc/sys/kernel/osrelease ]] && grep -qi microsoft /proc/sys/kernel/osrelease; then
  err "WSL detected. This script must run on a Raspberry Pi."
fi

if ! grep -qi "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
  warn "Raspberry Pi not detected. Proceeding anyway."
fi

if [[ "$(id -u)" -ne 0 ]] && ! sudo -n true 2>/dev/null; then
  err "Root privileges required. Run with sudo or enable passwordless sudo for flashing."
fi

USER_HOME="$(discover_user_home)"
SATURN_DIR="$(resolve_saturn_dir "$USER_HOME" || true)"
if [[ -z "$SATURN_DIR" ]]; then
  err "Saturn repo not found. Set SATURN_DIR or SATURN_FPGA_DIR."
fi

if [[ -n "${SATURN_FPGA_DIR:-}" ]]; then
  FPGA_DIR="$SATURN_FPGA_DIR"
else
  FPGA_DIR="${SATURN_DIR}/FPGA"
fi
SPILOAD_BIN="${SATURN_DIR}/sw_tools/spiload"

if [[ "$USE_PRIMARY" == true && "$USE_FALLBACK" == true ]]; then
  err "Choose only one: --primary or --fallback"
fi
if [[ "$USE_PRIMARY" == false && "$USE_FALLBACK" == false ]]; then
  USE_PRIMARY=true
fi

OFFSET="$PRIMARY_OFFSET"
TARGET_NAME="PRIMARY"
if [[ "$USE_FALLBACK" == true ]]; then
  OFFSET="$FALLBACK_OFFSET"
  TARGET_NAME="FALLBACK"
fi

if [[ ! -d "$FPGA_DIR" ]]; then
  err "FPGA directory not found: $FPGA_DIR"
fi

if [[ -z "$IMAGE" || "$IMAGE" == "latest" ]]; then
  # Pick newest plausible image file
  IMAGE="$(ls -t "$FPGA_DIR"/*.{bin,rbf,bit} 2>/dev/null | head -n1 || true)"
  [[ -n "$IMAGE" ]] || err "No FPGA image found in $FPGA_DIR"
fi

if [[ "$IMAGE" != /* ]]; then
  if [[ -f "$FPGA_DIR/$IMAGE" ]]; then
    IMAGE="$FPGA_DIR/$IMAGE"
  fi
fi

if [[ ! -f "$IMAGE" ]]; then
  err "Image not found: $IMAGE"
fi

progress 15

# Ensure spiload is built
if [[ ! -x "$SPILOAD_BIN" ]]; then
  info "Building spiload..."
  if [[ "$DRY_RUN" == true ]]; then
    info "[Dry Run] make -C ${SATURN_DIR}/sw_tools spiload"
  else
    make -C "${SATURN_DIR}/sw_tools" spiload
  fi
fi

if [[ ! -x "$SPILOAD_BIN" && "$DRY_RUN" == false ]]; then
  err "spiload not found or not executable at $SPILOAD_BIN"
fi

progress 25

SHA="$(sha256sum "$IMAGE" | awk '{print $1}')"
SHORT="${SHA:0:6}"

info "FPGA image: $IMAGE"
info "SHA256: $SHA"
info "Target: $TARGET_NAME offset=$OFFSET"
info "Verification: ON"

if [[ "$CONFIRM" != "FLASH" && "$CONFIRM" != "$SHORT" ]]; then
  err "Confirmation required. Re-run with: --confirm FLASH (or --confirm ${SHORT})"
fi

progress 35

CMD=("$SPILOAD_BIN" -v -o "$OFFSET" -f "$IMAGE")
info "Running: ${CMD[*]}"

if [[ "$DRY_RUN" == true ]]; then
  info "[Dry Run] Flash skipped."
  progress 100
  exit 0
fi

if ! run_as_root "${CMD[@]}"; then
  err "spiload failed"
fi

progress 100
info "FPGA flash complete."
