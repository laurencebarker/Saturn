#!/usr/bin/env bash
#
# qemu_pi_boot.sh
# Helper to extract kernel/dtb from a Raspberry Pi OS image and boot it in QEMU (Pi 4).
#
# Usage:
#   ./qemu_pi_boot.sh --img /path/to/raspios.img[.xz] [--work-dir /tmp/rpi-qemu]
#                    [--memory 2048] [--cpus 4] [--machine raspi4]
#                    [--extra-append "console=ttyAMA0,115200"]
#
set -euo pipefail

IMG=""
WORK_DIR=""
MEMORY=2048
CPUS=4
MACHINE="raspi4"
EXTRA_APPEND=""
DRY_RUN=0

die() { echo "[ERR] $*" >&2; exit 1; }
info() { echo "[INFO] $*"; }
ok() { echo "[OK] $*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --img)
      [[ $# -ge 2 ]] || die "--img requires a value"
      IMG="$2"
      shift 2
      ;;
    --work-dir)
      [[ $# -ge 2 ]] || die "--work-dir requires a value"
      WORK_DIR="$2"
      shift 2
      ;;
    --memory)
      [[ $# -ge 2 ]] || die "--memory requires a value"
      MEMORY="$2"
      shift 2
      ;;
    --cpus)
      [[ $# -ge 2 ]] || die "--cpus requires a value"
      CPUS="$2"
      shift 2
      ;;
    --machine)
      [[ $# -ge 2 ]] || die "--machine requires a value"
      MACHINE="$2"
      shift 2
      ;;
    --extra-append)
      [[ $# -ge 2 ]] || die "--extra-append requires a value"
      EXTRA_APPEND="$2"
      shift 2
      ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help)
      sed -n '1,30p' "$0"
      exit 0
      ;;
    *) die "Unknown arg: $1" ;;
  esac
done

[[ -n "$IMG" ]] || die "--img is required"
[[ -f "$IMG" ]] || die "Image not found: $IMG"

for bin in qemu-system-aarch64 qemu-img xz losetup mount; do
  command -v "$bin" >/dev/null 2>&1 || die "Missing dependency: $bin"
done

if [[ -z "$WORK_DIR" ]]; then
  WORK_DIR="/tmp/rpi-qemu-$(date +%Y%m%d-%H%M%S)"
fi

mkdir -p "$WORK_DIR"
BOOT_MNT="$WORK_DIR/boot"
mkdir -p "$BOOT_MNT"

IMG_BASENAME="$(basename "$IMG")"
IMG_WORK="$WORK_DIR/${IMG_BASENAME%.xz}"

cleanup() {
  set +e
  if mountpoint -q "$BOOT_MNT"; then
    sudo umount "$BOOT_MNT" || true
  fi
  if [[ -n "${LOOP_DEV:-}" ]]; then
    sudo losetup -d "$LOOP_DEV" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [[ "$IMG" == *.xz ]]; then
  info "Decompressing image to $IMG_WORK"
  [[ $DRY_RUN -eq 0 ]] && xz -dkc "$IMG" > "$IMG_WORK"
else
  info "Copying image to $IMG_WORK"
  [[ $DRY_RUN -eq 0 ]] && cp -f "$IMG" "$IMG_WORK"
fi

info "Setting up loop device"
if [[ $DRY_RUN -eq 0 ]]; then
  LOOP_DEV=$(sudo losetup --find --show --partscan "$IMG_WORK")
else
  LOOP_DEV="/dev/loopX"
fi

BOOT_DEV="${LOOP_DEV}p1"
if [[ $DRY_RUN -eq 0 ]]; then
  for _ in {1..20}; do
    [[ -b "$BOOT_DEV" ]] && break
    sleep 0.1
  done
  if [[ ! -b "$BOOT_DEV" ]]; then
    die "Boot partition not found for $LOOP_DEV"
  fi
  sudo mount "$BOOT_DEV" "$BOOT_MNT"
fi

KERNEL="$WORK_DIR/kernel8.img"
DTB="$WORK_DIR/bcm2711-rpi-4-b.dtb"

info "Extracting kernel and dtb"
if [[ $DRY_RUN -eq 0 ]]; then
  [[ -f "$BOOT_MNT/kernel8.img" ]] || die "kernel8.img not found in boot partition"
  [[ -f "$BOOT_MNT/bcm2711-rpi-4-b.dtb" ]] || die "bcm2711-rpi-4-b.dtb not found in boot partition"
  cp -f "$BOOT_MNT/kernel8.img" "$KERNEL"
  cp -f "$BOOT_MNT/bcm2711-rpi-4-b.dtb" "$DTB"
fi

ROOT_APPEND="console=ttyAMA0,115200 root=/dev/mmcblk0p2 rootwait rw"
APPEND="$ROOT_APPEND $EXTRA_APPEND"

ok "Launching QEMU"
echo
echo "Command:"
echo "qemu-system-aarch64 -M $MACHINE -cpu cortex-a72 -m $MEMORY -smp $CPUS -kernel $KERNEL -dtb $DTB -sd $IMG_WORK -append \"$APPEND\" -nographic"
echo

if [[ $DRY_RUN -eq 0 ]]; then
  exec qemu-system-aarch64 \
    -M "$MACHINE" \
    -cpu cortex-a72 \
    -m "$MEMORY" \
    -smp "$CPUS" \
    -kernel "$KERNEL" \
    -dtb "$DTB" \
    -sd "$IMG_WORK" \
    -append "$APPEND" \
    -nographic
fi
