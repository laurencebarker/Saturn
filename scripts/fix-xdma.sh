#!/usr/bin/env bash
# fix-xdma.sh
# Version: 2.1
# Rebuild & (re)install XDMA kernel module, stop/start p2app.service, and verify it's running.
# Usage: sudo bash /home/pi/github/Saturn/scripts/fix-xdma.sh
# Author: Jerry DeLong, KD4YAL

set -euo pipefail

SERVICE_NAME="p2app.service"

RED=$'\033[0;31m'; GRN=$'\033[0;32m'; YLW=$'\033[0;33m'; CYA=$'\033[0;36m'; NC=$'\033[0m'
info(){ printf "${CYA}[INFO]${NC} %s\n" "$*"; }
ok()  { printf "${GRN}[ OK ]${NC} %s\n" "$*"; }
warn(){ printf "${YLW}[WARN]${NC} %s\n" "$*"; }
die(){ printf "${RED}[ERR ] %s${NC}\n" "$*" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }

need_root(){ [[ $(id -u) -eq 0 ]] || die "Please run as root (sudo)."; }

resolve_user_home(){
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    getent passwd "${SUDO_USER}" | cut -d: -f6
  else
    getent passwd "pi" | cut -d: -f6 || echo "${HOME}"
  fi
}

resolve_driver_dir(){
  local uh; uh="$(resolve_user_home)"
  local d="${uh}/github/Saturn/linuxdriver/xdma"
  [[ -d "$d" ]] || die "Driver directory not found: $d"
  printf "%s" "$d"
}

ensure_headers(){
  local krel kbuild; krel="$(uname -r)"; kbuild="/lib/modules/${krel}/build"
  if [[ ! -d "$kbuild" ]]; then
    warn "Kernel headers for ${krel} not found. Installing…"
    apt-get update -y || die "apt update failed"
    if apt-cache show raspberrypi-kernel-headers >/dev/null 2>&1; then
      apt-get install -y raspberrypi-kernel-headers || die "raspberrypi-kernel-headers install failed"
    else
      apt-get install -y "linux-headers-${krel}" || die "linux-headers-${krel} install failed"
    fi
    [[ -d "$kbuild" ]] || die "Headers still missing after install."
  fi
  ok "Kernel headers present for ${krel}."
}

# Emits logs to STDERR, returns include dir on STDOUT
ensure_xdma_header(){
  local driver_dir="$1"
  local sys_inc_dir="/usr/local/include/xdma"
  local sys_hdr="${sys_inc_dir}/libxdma_api.h"
  mkdir -p "$sys_inc_dir"

  if [[ -f "$sys_hdr" ]]; then
    ok "Found header: ${sys_hdr}" >&2; printf "%s" "$sys_inc_dir"; return 0
  fi

  # Search repo
  local root found=""; root="$(dirname "$driver_dir")"
  while IFS= read -r p; do found="$p"; break; done < <(find "$root" -maxdepth 5 -type f -name libxdma_api.h 2>/dev/null | head -n1)
  if [[ -n "$found" ]]; then
    info "Staging libxdma_api.h from ${found}" >&2
    cp -f "$found" "$sys_hdr"; ok "Header staged at ${sys_hdr}" >&2
    printf "%s" "$sys_inc_dir"; return 0
  fi

  # Fetch
  info "libxdma_api.h not found locally; attempting download…" >&2
  local url1="https://raw.githubusercontent.com/Xilinx/dma_ip_drivers/master/XDMA/linux-kernel/include/libxdma_api.h"
  local url2="https://gitlab.esss.lu.se/icshwi/dma_ip_drivers/-/raw/master/XDMA/linux-kernel/include/libxdma_api.h?inline=false"
  if have curl; then
    curl -fsSL "$url1" -o "$sys_hdr" || curl -fsSL "$url2" -o "$sys_hdr" || die "Failed to download libxdma_api.h"
  elif have wget; then
    wget -q -O "$sys_hdr" "$url1" || wget -q -O "$sys_hdr" "$url2" || die "Failed to download libxdma_api.h"
  else
    apt-get update -y && apt-get install -y curl || die "Could not install curl"
    curl -fsSL "$url1" -o "$sys_hdr" || curl -fsSL "$url2" -o "$sys_hdr" || die "Failed to download libxdma_api.h"
  fi
  ok "Header downloaded to ${sys_hdr}" >&2
  printf "%s" "$sys_inc_dir"
}

run_make(){
  # Quiet the XVC_FLAGS and System.map chatter; set VERBOSE=1 to see everything.
  if [[ "${VERBOSE:-0}" == "1" ]]; then
    make "$@"
  else
    env MAKEFLAGS="${MAKEFLAGS:-} -s" make "$@" 2>&1 | \
      awk '!/Makefile:[0-9]+: XVC_FLAGS: \./ && !/Warning: modules_install: missing '\''System.map'\'' file\. Skipping depmod\./ { print }'
  fi
}

service_exists(){ systemctl list-unit-files --type=service | awk '{print $1}' | grep -qx "$SERVICE_NAME"; }
service_active(){ systemctl is-active --quiet "$SERVICE_NAME"; }

stop_service_if_running(){
  if service_exists; then
    if service_active; then
      info "Stopping ${SERVICE_NAME}…"
      systemctl stop "$SERVICE_NAME" || die "Failed to stop ${SERVICE_NAME}"
      WAS_ACTIVE=1
    else
      WAS_ACTIVE=0
      warn "${SERVICE_NAME} is not active."
    fi
  else
    WAS_ACTIVE=0
    warn "${SERVICE_NAME} not found. Skipping stop/start."
  fi
}

start_service_and_verify(){
  if [[ "${WAS_ACTIVE}" -eq 1 ]]; then
    info "Starting ${SERVICE_NAME}…"
    systemctl start "$SERVICE_NAME" || die "Failed to start ${SERVICE_NAME}"
  else
    # If it wasn't active before but the unit exists, still start it (you asked to restart)
    if service_exists; then
      info "Starting ${SERVICE_NAME} (was not active before)…"
      systemctl start "$SERVICE_NAME" || die "Failed to start ${SERVICE_NAME}"
    fi
  fi

  if service_exists; then
    if service_active; then
      ok "${SERVICE_NAME} is active."
    else
      die "${SERVICE_NAME} is not active after start. Check: journalctl -u ${SERVICE_NAME} -n 50 --no-pager"
    fi
  fi
}

unload_xdma_if_loaded(){
  if lsmod | awk '{print $1}' | grep -qx xdma; then
    info "Unloading xdma…"
    if ! modprobe -r xdma; then
      warn "xdma is still in use by some process. Will continue build; reload attempt may fail."
    fi
  fi
}

reload_xdma_module(){
  # Always try a fresh reload after install
  if lsmod | awk '{print $1}' | grep -qx xdma; then
    info "Unloading xdma for fresh reload…"
    modprobe -r xdma || warn "Could not unload xdma; another process may be holding /dev/xdma*"
  fi
  info "Loading xdma…"
  modprobe xdma || die "xdma failed to load; check dmesg"
  if lsmod | awk '{print $1}' | grep -qx xdma; then
    ok "xdma loaded."
  else
    die "xdma not present after modprobe."
  fi
}

main(){
  need_root
  ensure_headers

  local driver_dir krel kbuild
  driver_dir="$(resolve_driver_dir)"; krel="$(uname -r)"; kbuild="/lib/modules/${krel}/build"

  info "Kernel: ${krel}"
  info "Driver: ${driver_dir}"

  # Ensure API header
  local xdma_inc; xdma_inc="$(ensure_xdma_header "${driver_dir}")"
  info "Using include dir: ${xdma_inc}"

  # 1) Stop service (so it releases /dev/xdma*)
  WAS_ACTIVE=0
  stop_service_if_running

  # 2) Try to unload the module now that p2app is stopped
  unload_xdma_if_loaded

  # 3) Build & install
  cd "${driver_dir}"
  info "Cleaning previous build…"
  run_make -C "${kbuild}" M="${driver_dir}" clean || warn "make clean reported issues; continuing"

  info "Building xdma.ko…"
  run_make -C "${kbuild}" M="${driver_dir}" \
    EXTRA_CFLAGS="-I${xdma_inc} -Wno-empty-body -Wno-missing-prototypes -Wno-missing-declarations" \
    KBUILD_VERBOSE=0 \
    modules

  info "Installing module…"
  run_make -C "${kbuild}" M="${driver_dir}" DEPMOD=/bin/true modules_install

  info "Running depmod…"
  depmod -A

  # 4) Reload module
  reload_xdma_module

  # 5) Start service and verify
  start_service_and_verify

  # Friendly summary
  modinfo -n xdma 2>/dev/null | xargs -I{} printf "%s%s%s\n" "${CYA}" "Module file: {}" "${NC}" || true
  ok "Done: XDMA updated, ${SERVICE_NAME} running."
}

main "$@"
