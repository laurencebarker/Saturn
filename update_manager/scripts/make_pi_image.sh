#!/usr/bin/env bash
set -euo pipefail

# make_pi_image.sh - Create a minimal-size Pi OS image using pishrink
# Version: 1.0.0
# Intended for Raspberry Pi OS (Bookworm/Trixie). Not for WSL/desktop.

SRC_DEV="/dev/mmcblk0"
OUT_DIR="${HOME}"
NO_SHRINK=false
COMPRESS=false
SUDO=""

progress(){ echo "Progress: $1%"; }
info(){ echo "$@"; }
warn(){ echo "WARN: $@"; }
err(){ echo "ERR: $@" >&2; exit 1; }

if [[ "$(id -u)" -ne 0 ]]; then
  if sudo -n true 2>/dev/null; then
    SUDO="sudo -n"
  else
    err "Root privileges required. Run with sudo or enable passwordless sudo."
  fi
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir)
      [[ $# -ge 2 ]] || err "--out-dir requires a path"
      OUT_DIR="$2"
      shift 2
      ;;
    --no-shrink)
      NO_SHRINK=true
      shift
      ;;
    --compress)
      COMPRESS=true
      shift
      ;;
    *)
      err "Unknown argument: $1"
      ;;
  esac
done

DATE="$(date +%Y%m%d-%H%M%S)"
OUT_IMG="${OUT_DIR}/saturn-pi-${DATE}.img"

progress 5

if [[ -f /proc/sys/kernel/osrelease ]] && grep -qi microsoft /proc/sys/kernel/osrelease; then
  err "WSL detected. This script must run on a Raspberry Pi."
fi

if [[ ! -b "$SRC_DEV" ]]; then
  err "Source device $SRC_DEV not found."
fi

CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-unknown}")"
if [[ "$CODENAME" != "bookworm" && "$CODENAME" != "trixie" ]]; then
  warn "OS codename '$CODENAME' is not Bookworm/Trixie. Proceeding anyway."
fi

progress 10

ROOT_AVAIL_BYTES="$(df -B1 "$OUT_DIR" | awk 'NR==2 {print $4}')"
SRC_BYTES="$($SUDO blockdev --getsize64 "$SRC_DEV")"

info "OS codename: ${CODENAME}"
info "Source: ${SRC_DEV} (${SRC_BYTES} bytes)"
info "Dest:   ${OUT_IMG}"

if [[ "$ROOT_AVAIL_BYTES" -lt "$SRC_BYTES" ]]; then
  err "Not enough space in $OUT_DIR. Need ${SRC_BYTES} bytes, have ${ROOT_AVAIL_BYTES}."
fi

progress 15

# Ensure pishrink exists
if ! command -v pishrink >/dev/null 2>&1; then
  info "Installing PiShrink..."
  wget -q https://raw.githubusercontent.com/Drewsif/PiShrink/master/pishrink.sh -O /tmp/pishrink.sh
  chmod +x /tmp/pishrink.sh
  sudo mv /tmp/pishrink.sh /usr/local/bin/pishrink
fi

progress 20

info "Imaging ${SRC_DEV} -> ${OUT_IMG}"

# Use pv if available for progress/ETA; else dd with status=progress
if command -v pv >/dev/null 2>&1; then
  pv -ptebar "$SRC_DEV" | $SUDO dd of="$OUT_IMG" bs=4M conv=fsync status=none
else
  $SUDO dd if="$SRC_DEV" of="$OUT_IMG" bs=4M status=progress conv=fsync
fi

progress 75

if ! $NO_SHRINK; then
  info "Shrinking image..."
  $SUDO pishrink "$OUT_IMG"
else
  warn "Skipping shrink (--no-shrink)"
fi

if $COMPRESS; then
  info "Compressing image (.xz)..."
  if command -v xz >/dev/null 2>&1; then
    xz -T0 -z -f "$OUT_IMG"
    OUT_IMG="${OUT_IMG}.xz"
  else
    warn "xz not found; skipping compression."
  fi
fi

progress 100
info "Done: ${OUT_IMG}"
