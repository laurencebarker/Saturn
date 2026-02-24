#!/usr/bin/env bash
set -Eeuo pipefail

# Optional environment file written by cloud-init user-data.
if [[ -f /etc/default/saturn-provision ]]; then
  # shellcheck disable=SC1091
  source /etc/default/saturn-provision
fi

SATURN_USER="${SATURN_USER:-pi}"
SATURN_REPO_URL="${SATURN_REPO_URL:-https://github.com/kd4yal2024/Saturn.git}"
SATURN_REPO_BRANCH="${SATURN_REPO_BRANCH:-main}"
SATURN_REPO_DIR="${SATURN_REPO_DIR:-}"

SATURN_INSTALL_UPDATE_MANAGER="${SATURN_INSTALL_UPDATE_MANAGER:-1}"
SATURN_INSTALL_P2APP_CONTROL="${SATURN_INSTALL_P2APP_CONTROL:-1}"
SATURN_INSTALL_UDEV_RULES="${SATURN_INSTALL_UDEV_RULES:-1}"
SATURN_REBUILD_XDMA="${SATURN_REBUILD_XDMA:-1}"
SATURN_BUILD_OPTIONAL_TOOLS="${SATURN_BUILD_OPTIONAL_TOOLS:-1}"

SATURN_FLASH_FPGA="${SATURN_FLASH_FPGA:-0}"
SATURN_FLASH_IMAGE="${SATURN_FLASH_IMAGE:-latest}"
SATURN_FLASH_FALLBACK="${SATURN_FLASH_FALLBACK:-0}"
SATURN_FLASH_CONFIRM="${SATURN_FLASH_CONFIRM:-}"

SATURN_ADMIN_PASSWORD="${SATURN_ADMIN_PASSWORD:-}"
SATURN_FORCE_REPROVISION="${SATURN_FORCE_REPROVISION:-0}"
SATURN_STATE_DIR="${SATURN_STATE_DIR:-/var/lib/saturn-provision}"
SATURN_LOG_FILE="${SATURN_LOG_FILE:-/var/log/saturn-provision.log}"

apt_updated=0
PYTHON_GUARD_DIR=""

log() { printf '[%(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$*"; }
die() { log "ERROR: $*"; exit 1; }

# Keep Python from dropping bytecode into source trees.
export PYTHONDONTWRITEBYTECODE=1
export PYTHONPYCACHEPREFIX="${PYTHONPYCACHEPREFIX:-/var/cache/saturn-python}"

bool_true() {
  case "${1:-0}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

run_as_user() {
  local home="$1"
  shift
  sudo -u "$SATURN_USER" -H env HOME="$home" "$@"
}

ensure_root() {
  [[ "$(id -u)" -eq 0 ]] || die "Run as root."
}

ensure_user() {
  if ! id -u "$SATURN_USER" >/dev/null 2>&1; then
    die "User '$SATURN_USER' does not exist. Create it in cloud-init first."
  fi
  getent passwd "$SATURN_USER" | cut -d: -f6
}

assert_not_repo_python_script() {
  local script="$1"
  if [[ -n "${SATURN_REPO_DIR:-}" && "$script" == "$SATURN_REPO_DIR/"* && "$script" == *.py ]]; then
    die "Refusing to execute Python script from repo tree: $script"
  fi
}

install_python_guard_wrapper() {
  local wrapper_path="$1"
  local real_python="$2"
  cat > "$wrapper_path" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="\${SATURN_REPO_DIR:-}"
repo_real=""
if [[ -n "\$repo_dir" ]]; then
  repo_real="\$(readlink -f "\$repo_dir" 2>/dev/null || true)"
fi

for arg in "\$@"; do
  [[ "\$arg" == *.py ]] || continue
  candidate="\$arg"
  if [[ "\$candidate" != /* ]]; then
    candidate="\$(pwd)/\$candidate"
  fi
  resolved="\$(readlink -f "\$candidate" 2>/dev/null || true)"
  if [[ -n "\$resolved" && -n "\$repo_real" && "\$resolved" == "\$repo_real/"* ]]; then
    echo "ERROR: Refusing Python script execution from repo tree: \$resolved" >&2
    exit 101
  fi
done

exec "$real_python" "\$@"
EOF
  chmod 0755 "$wrapper_path"
}

enable_python_repo_guard() {
  local python3_real python_real
  python3_real="$(command -v python3 || true)"
  [[ -n "$python3_real" ]] || die "python3 is required but not found in PATH"
  python_real="$(command -v python || true)"

  PYTHON_GUARD_DIR="$(mktemp -d /tmp/saturn-python-guard.XXXXXX)"
  install_python_guard_wrapper "$PYTHON_GUARD_DIR/python3" "$python3_real"
  if [[ -n "$python_real" ]]; then
    install_python_guard_wrapper "$PYTHON_GUARD_DIR/python" "$python_real"
  else
    ln -s python3 "$PYTHON_GUARD_DIR/python"
  fi
  export PATH="$PYTHON_GUARD_DIR:$PATH"
}

cleanup_python_guard() {
  if [[ -n "${PYTHON_GUARD_DIR:-}" && -d "$PYTHON_GUARD_DIR" ]]; then
    rm -rf "$PYTHON_GUARD_DIR" || true
  fi
}

apt_update_once() {
  if [[ "$apt_updated" -eq 0 ]]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt_updated=1
  fi
}

apt_install() {
  apt_update_once
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y --no-install-recommends "$@"
}

ensure_packages() {
  log "Installing build/runtime dependencies"
  apt_install \
    git rsync curl wget ca-certificates sudo \
    build-essential pkg-config gcc g++ make \
    python3 python3-venv python3-pip python3-psutil \
    libgpiod-dev libi2c-dev libgtk-3-dev libglib2.0-bin lxterminal \
    libasound2-dev libpulse-dev libusb-1.0-0-dev libcurl4-openssl-dev \
    desktop-file-utils xdg-user-dirs

  if bool_true "$SATURN_INSTALL_UPDATE_MANAGER"; then
    apt_install nginx apache2-utils rustc cargo
  fi
}

ensure_kernel_headers() {
  local krel build_dir
  krel="$(uname -r)"
  build_dir="/lib/modules/${krel}/build"
  if [[ -d "$build_dir" ]]; then
    log "Kernel headers already present for $krel"
    return
  fi

  log "Installing kernel headers for $krel"
  apt_update_once
  export DEBIAN_FRONTEND=noninteractive
  if ! apt-get install -y --no-install-recommends "linux-headers-${krel}"; then
    apt-get install -y --no-install-recommends raspberrypi-kernel-headers || true
  fi
  [[ -d "$build_dir" ]] || die "Kernel headers still missing at $build_dir"
}

ensure_repo() {
  local saturn_home="$1"
  local repo_parent
  if [[ -z "$SATURN_REPO_DIR" ]]; then
    SATURN_REPO_DIR="${saturn_home}/github/Saturn"
  fi
  repo_parent="$(dirname "$SATURN_REPO_DIR")"

  install -d -m 0755 -o "$SATURN_USER" -g "$SATURN_USER" "$repo_parent"

  if [[ -d "${SATURN_REPO_DIR}/.git" ]]; then
    log "Updating repo at $SATURN_REPO_DIR -> ${SATURN_REPO_BRANCH}"
    run_as_user "$saturn_home" git -C "$SATURN_REPO_DIR" fetch --depth 1 origin "$SATURN_REPO_BRANCH"
    run_as_user "$saturn_home" git -C "$SATURN_REPO_DIR" checkout -B "$SATURN_REPO_BRANCH" "origin/${SATURN_REPO_BRANCH}"
  else
    log "Cloning repo $SATURN_REPO_URL ($SATURN_REPO_BRANCH) into $SATURN_REPO_DIR"
    run_as_user "$saturn_home" git clone --depth 1 --branch "$SATURN_REPO_BRANCH" "$SATURN_REPO_URL" "$SATURN_REPO_DIR"
  fi
}

prepare_python_env() {
  local saturn_home="$1"
  local venv_dir="${saturn_home}/venv"

  log "Preparing Python virtual environment at $venv_dir"
  if [[ ! -d "$venv_dir" ]]; then
    run_as_user "$saturn_home" python3 -m venv "$venv_dir"
  fi
  run_as_user "$saturn_home" "$venv_dir/bin/pip" install --upgrade pip
  run_as_user "$saturn_home" "$venv_dir/bin/pip" install rich==13.8.1 psutil pyfiglet
}

build_dir() {
  local label="$1"
  local dir="$2"
  local nproc="$3"
  [[ -d "$dir" ]] || die "$label directory missing: $dir"
  log "Building $label ($dir)"
  make -C "$dir" clean >/dev/null 2>&1 || true
  make -C "$dir" -j"$nproc"
}

build_saturn_apps() {
  local nproc="$1"

  build_dir "P2_app"      "$SATURN_REPO_DIR/sw_projects/P2_app" "$nproc"
  build_dir "P1_app"      "$SATURN_REPO_DIR/sw_projects/P1_app" "$nproc"
  build_dir "audiotest"   "$SATURN_REPO_DIR/sw_projects/audiotest" "$nproc"
  build_dir "biascheck"   "$SATURN_REPO_DIR/sw_projects/biascheck" "$nproc"
  build_dir "codectest"   "$SATURN_REPO_DIR/sw_projects/codectest" "$nproc"
  build_dir "axi_rw"      "$SATURN_REPO_DIR/sw_tools/axi_rw" "$nproc"
  build_dir "flashwriter" "$SATURN_REPO_DIR/sw_tools/flashwriter" "$nproc"
  build_dir "load-FPGA"   "$SATURN_REPO_DIR/sw_tools/load-FPGA" "$nproc"
  build_dir "spiload"     "$SATURN_REPO_DIR/sw_tools/spiload" "$nproc"

  if bool_true "$SATURN_BUILD_OPTIONAL_TOOLS"; then
    build_dir "FPGAVersion"   "$SATURN_REPO_DIR/sw_tools/FPGAVersion" "$nproc"
    build_dir "IQdmatest"     "$SATURN_REPO_DIR/sw_tools/IQdmatest" "$nproc"
    build_dir "codecwrite"    "$SATURN_REPO_DIR/sw_tools/codecwrite" "$nproc"
    build_dir "spiadcread"    "$SATURN_REPO_DIR/sw_tools/spiadcread" "$nproc"
    build_dir "linuxdriver tools" "$SATURN_REPO_DIR/linuxdriver/tools" "$nproc"
  fi
}

build_and_install_xdma() {
  local nproc="$1"
  local xdma_dir="$SATURN_REPO_DIR/linuxdriver/xdma"
  [[ -d "$xdma_dir" ]] || die "XDMA directory missing: $xdma_dir"

  ensure_kernel_headers
  log "Building XDMA kernel module"
  make -C "$xdma_dir" clean >/dev/null 2>&1 || true
  make -C "$xdma_dir" -j"$nproc"
  make -C "$xdma_dir" install
  depmod -A

  install -d -m 0755 /etc/modules-load.d
  printf 'xdma\n' > /etc/modules-load.d/xdma.conf
  modprobe -r xdma >/dev/null 2>&1 || true
  modprobe xdma || die "Failed to load xdma module"
  log "XDMA module installed and loaded"
}

install_desktop_shortcuts() {
  local saturn_home="$1"
  local script="$SATURN_REPO_DIR/scripts/update-desktop-apps.sh"
  if [[ -x "$script" ]]; then
    assert_not_repo_python_script "$script"
    log "Installing/repairing desktop launchers"
    run_as_user "$saturn_home" env SATURN_ROOT="$SATURN_REPO_DIR" bash "$script"
  else
    log "WARN: Missing script: $script"
  fi
}

install_udev_rules() {
  local script="$SATURN_REPO_DIR/rules/install-rules.sh"
  if [[ -x "$script" ]]; then
    assert_not_repo_python_script "$script"
    log "Installing udev rules"
    bash "$script"
  else
    log "WARN: Missing udev script: $script"
  fi
}

install_p2app_control() {
  local saturn_home="$1"
  local script="$SATURN_REPO_DIR/sw_tools/p2app-control/install.sh"
  if [[ -x "$script" ]]; then
    assert_not_repo_python_script "$script"
    log "Installing p2app-control and p2app.service"
    env HOME="$saturn_home" SUDO_USER="$SATURN_USER" bash "$script"
  else
    log "WARN: Missing p2app-control installer: $script"
  fi
}

install_update_manager() {
  local saturn_home="$1"
  local script="$SATURN_REPO_DIR/update_manager/install_saturn_go_nginx.sh"
  if [[ ! -x "$script" ]]; then
    die "Update manager installer not found/executable: $script"
  fi
  assert_not_repo_python_script "$script"
  log "Installing Saturn Update Manager"
  env \
    HOME="$saturn_home" \
    SUDO_USER="$SATURN_USER" \
    SATURN_SERVICE_USER="$SATURN_USER" \
    SATURN_ADMIN_PASSWORD="$SATURN_ADMIN_PASSWORD" \
    bash "$script"
}

maybe_flash_fpga() {
  local flash_script="$SATURN_REPO_DIR/update_manager/scripts/flash_fpga.sh"
  [[ -x "$flash_script" ]] || die "flash_fpga.sh not found/executable: $flash_script"
  assert_not_repo_python_script "$flash_script"
  [[ -n "$SATURN_FLASH_CONFIRM" ]] || die "SATURN_FLASH_CONFIRM is required when SATURN_FLASH_FPGA=1"

  local cmd=(bash "$flash_script" --confirm "$SATURN_FLASH_CONFIRM")
  if [[ "$SATURN_FLASH_IMAGE" == "latest" ]]; then
    cmd+=(--latest)
  else
    cmd+=(--image "$SATURN_FLASH_IMAGE")
  fi
  if bool_true "$SATURN_FLASH_FALLBACK"; then
    cmd+=(--fallback)
  else
    cmd+=(--primary)
  fi

  log "Flashing FPGA using load-FPGA"
  "${cmd[@]}"
}

cleanup_python_artifacts_in_repo() {
  [[ -n "${SATURN_REPO_DIR:-}" && -d "$SATURN_REPO_DIR" ]] || return 0
  find "$SATURN_REPO_DIR" -type d -name "__pycache__" -prune -exec rm -rf {} + 2>/dev/null || true
  find "$SATURN_REPO_DIR" -type f \( -name "*.pyc" -o -name "*.pyo" \) -delete 2>/dev/null || true
}

write_completion_state() {
  local saturn_home="$1"
  local commit
  commit="$(run_as_user "$saturn_home" git -C "$SATURN_REPO_DIR" rev-parse --short HEAD 2>/dev/null || true)"
  install -d -m 0755 "$SATURN_STATE_DIR"
  cat > "${SATURN_STATE_DIR}/complete" <<EOF
completed_at=$(date --iso-8601=seconds)
saturn_user=${SATURN_USER}
repo_url=${SATURN_REPO_URL}
repo_branch=${SATURN_REPO_BRANCH}
repo_dir=${SATURN_REPO_DIR}
repo_commit=${commit:-unknown}
EOF
}

main() {
  ensure_root
  install -d -m 0755 "$(dirname "$SATURN_LOG_FILE")" "$SATURN_STATE_DIR"
  install -d -m 0755 "$PYTHONPYCACHEPREFIX"
  touch "$SATURN_LOG_FILE"
  exec > >(tee -a "$SATURN_LOG_FILE") 2>&1

  trap cleanup_python_guard EXIT
  trap 'die "Line $LINENO failed while running: ${BASH_COMMAND}"' ERR

  if [[ -f "${SATURN_STATE_DIR}/complete" ]] && ! bool_true "$SATURN_FORCE_REPROVISION"; then
    log "Provisioning already completed. Set SATURN_FORCE_REPROVISION=1 to run again."
    exit 0
  fi

  local saturn_home nproc
  saturn_home="$(ensure_user)"
  nproc="$(nproc 2>/dev/null || echo 1)"

  log "Starting Saturn provisioning for user '$SATURN_USER' (home: $saturn_home)"
  ensure_packages
  ensure_repo "$saturn_home"
  enable_python_repo_guard
  prepare_python_env "$saturn_home"
  build_saturn_apps "$nproc"
  install_desktop_shortcuts "$saturn_home"

  if bool_true "$SATURN_REBUILD_XDMA"; then
    build_and_install_xdma "$nproc"
  fi
  if bool_true "$SATURN_INSTALL_UDEV_RULES"; then
    install_udev_rules
  fi
  if bool_true "$SATURN_INSTALL_P2APP_CONTROL"; then
    install_p2app_control "$saturn_home"
  fi
  if bool_true "$SATURN_INSTALL_UPDATE_MANAGER"; then
    install_update_manager "$saturn_home"
  fi
  if bool_true "$SATURN_FLASH_FPGA"; then
    maybe_flash_fpga
  fi

  cleanup_python_artifacts_in_repo
  write_completion_state "$saturn_home"
  log "Saturn provisioning completed successfully."
  log "State file: ${SATURN_STATE_DIR}/complete"
  log "Provision log: $SATURN_LOG_FILE"
}

main "$@"
