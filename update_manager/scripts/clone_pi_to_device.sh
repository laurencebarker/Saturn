#!/usr/bin/env bash
set -euo pipefail

# clone_pi_to_device.sh - Clone /dev/mmcblk0 to a target device (e.g. /dev/sda)
# Version: 1.0.0
#
# Usage:
#   ./clone_pi_to_device.sh --target /dev/sdX
#
# Notes:
# - DEST device will be overwritten.
# - Requires root (or passwordless sudo).

SRC_DEV="/dev/mmcblk0"
TARGET=""
SUDO=""

progress(){ echo "Progress: $1%"; }
info(){ echo "$@"; }
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
    --target)
      [[ $# -ge 2 ]] || err "--target requires a device path"
      TARGET="$2"
      shift 2
      ;;
    *) err "Unknown argument: $1" ;;
  esac
done

progress 5

if [[ ! -b "$SRC_DEV" ]]; then
  err "Source device $SRC_DEV not found."
fi
if [[ -z "$TARGET" ]]; then
  err "Target device not specified."
fi
if [[ ! -b "$TARGET" ]]; then
  err "Target device $TARGET not found."
fi
if [[ "$TARGET" == "$SRC_DEV" ]]; then
  err "Target cannot be the same as source."
fi

SRC_BYTES="$($SUDO blockdev --getsize64 "$SRC_DEV")"
TGT_BYTES="$($SUDO blockdev --getsize64 "$TARGET")"
info "Source: ${SRC_DEV} (${SRC_BYTES} bytes)"
info "Target: ${TARGET} (${TGT_BYTES} bytes)"
if [[ "$TGT_BYTES" -lt "$SRC_BYTES" ]]; then
  err "Target device too small."
fi

progress 10

if command -v pv >/dev/null 2>&1; then
  info "Cloning with pv progress..."
  # pv -n prints integer percentage to stderr
  $SUDO pv -n -s "$SRC_BYTES" "$SRC_DEV" \
    | $SUDO dd of="$TARGET" bs=4M conv=fsync status=none \
    2> >(while read -r p; do progress "$p"; done)
else
  info "Cloning with dd status=progress..."
  $SUDO dd if="$SRC_DEV" of="$TARGET" bs=4M status=progress conv=fsync
fi

progress 100
info "Done"
