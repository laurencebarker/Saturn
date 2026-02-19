#!/usr/bin/env bash
# uninstall_saturn_go_nginx.sh
# Remove Saturn Rust + NGINX deployment created by install_saturn_go_nginx.sh.
#
# Usage:
#   sudo bash uninstall_saturn_go_nginx.sh [--purge] [--no-purge] [--keep-auth] [--remove-packages] [--dry-run] [--yes]

set -euo pipefail

PURGE=0
KEEP_AUTH=0
REMOVE_PACKAGES=0
DRY_RUN=0
ASSUME_YES=0

for arg in "$@"; do
  case "$arg" in
    --purge) PURGE=1 ;;
    --no-purge) PURGE=0 ;;
    --keep-auth) KEEP_AUTH=1 ;;
    --remove-packages) REMOVE_PACKAGES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --yes) ASSUME_YES=1 ;;
    *) echo "[ERROR] Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "[ERROR] Run as root (sudo)." >&2
  exit 1
fi

SYSTEMD_SERVICE="/etc/systemd/system/saturn-go.service"
WATCHDOG_SERVICE="/etc/systemd/system/saturn-go-watchdog.service"
WATCHDOG_TIMER="/etc/systemd/system/saturn-go-watchdog.timer"
NGINX_SITE_AVAILABLE="/etc/nginx/sites-available/saturn"
NGINX_SITE_ENABLED="/etc/nginx/sites-enabled/saturn"
NGINX_SSE_MAP="/etc/nginx/conf.d/saturn_sse_map.conf"
BASIC_AUTH_FILE="/etc/nginx/.htpasswd"
SATURN_ROOT="/opt/saturn-go"
WEB_ROOT="/var/lib/saturn-web"
WATCHDOG_SCRIPT_NEW="/usr/local/lib/saturn-go/saturn-health-watchdog.sh"
WATCHDOG_SCRIPT_OLD="/opt/saturn-go/scripts/saturn-health-watchdog.sh"
WATCHDOG_SCRIPT_DIR="/usr/local/lib/saturn-go"
SATURN_STATE_DIR="/var/lib/saturn-state"

run_cmd() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[DRY] $*"
  else
    "$@"
  fi
}

echo "This will uninstall the Saturn Rust + NGINX deployment."
echo "Options: purge=$PURGE keep-auth=$KEEP_AUTH remove-packages=$REMOVE_PACKAGES dry-run=$DRY_RUN"
if [[ $ASSUME_YES -ne 1 ]]; then
  read -rp "Proceed? [y/N] " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || { echo "[INFO] Cancelled."; exit 0; }
fi

# 1) Stop and disable service
if systemctl list-unit-files | grep -Fq "saturn-go.service"; then
  echo "[INFO] Stopping and disabling saturn-go.service"
  run_cmd systemctl stop saturn-go.service || true
  run_cmd systemctl disable saturn-go.service || true
fi
if systemctl list-unit-files | grep -Fq "saturn-go-watchdog.timer"; then
  echo "[INFO] Stopping and disabling saturn-go-watchdog.timer"
  run_cmd systemctl stop saturn-go-watchdog.timer || true
  run_cmd systemctl disable saturn-go-watchdog.timer || true
fi
if systemctl list-unit-files | grep -Fq "saturn-go-watchdog.service"; then
  echo "[INFO] Stopping and disabling saturn-go-watchdog.service"
  run_cmd systemctl stop saturn-go-watchdog.service || true
  run_cmd systemctl disable saturn-go-watchdog.service || true
fi

# 2) Kill straggler process if present
if pgrep -f "/opt/saturn-go/bin/saturn-go" >/dev/null 2>&1; then
  PIDS="$(pgrep -f "/opt/saturn-go/bin/saturn-go" | tr '\n' ' ')"
  echo "[INFO] Stopping lingering saturn-go process(es): $PIDS"
  if [[ $DRY_RUN -eq 0 ]]; then
    pgrep -f "/opt/saturn-go/bin/saturn-go" | xargs -r kill -TERM || true
    sleep 1
    pgrep -f "/opt/saturn-go/bin/saturn-go" | xargs -r kill -KILL || true
  fi
fi

# 3) Remove systemd unit
if [[ -f "$SYSTEMD_SERVICE" ]]; then
  echo "[INFO] Removing unit file: $SYSTEMD_SERVICE"
  run_cmd rm -f "$SYSTEMD_SERVICE"
fi
if [[ -f "$WATCHDOG_SERVICE" ]]; then
  echo "[INFO] Removing watchdog unit file: $WATCHDOG_SERVICE"
  run_cmd rm -f "$WATCHDOG_SERVICE"
fi
if [[ -f "$WATCHDOG_TIMER" ]]; then
  echo "[INFO] Removing watchdog timer file: $WATCHDOG_TIMER"
  run_cmd rm -f "$WATCHDOG_TIMER"
fi
for watchdog_script in "$WATCHDOG_SCRIPT_NEW" "$WATCHDOG_SCRIPT_OLD"; do
  if [[ -f "$watchdog_script" ]]; then
    echo "[INFO] Removing watchdog script: $watchdog_script"
    run_cmd rm -f "$watchdog_script"
  fi
done
if [[ -d "$WATCHDOG_SCRIPT_DIR" ]]; then
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[DRY] rmdir $WATCHDOG_SCRIPT_DIR (if empty)"
  else
    rmdir "$WATCHDOG_SCRIPT_DIR" >/dev/null 2>&1 || true
  fi
fi
run_cmd systemctl daemon-reload

# 4) Remove nginx config
if [[ -e "$NGINX_SITE_ENABLED" || -h "$NGINX_SITE_ENABLED" ]]; then
  echo "[INFO] Removing nginx enabled link: $NGINX_SITE_ENABLED"
  run_cmd rm -f "$NGINX_SITE_ENABLED"
fi
if [[ -f "$NGINX_SITE_AVAILABLE" ]]; then
  echo "[INFO] Removing nginx site file: $NGINX_SITE_AVAILABLE"
  run_cmd rm -f "$NGINX_SITE_AVAILABLE"
fi
if [[ -f "$NGINX_SSE_MAP" ]]; then
  echo "[INFO] Removing nginx SSE map file: $NGINX_SSE_MAP"
  run_cmd rm -f "$NGINX_SSE_MAP"
fi

# 5) Remove auth unless requested to keep
if [[ $KEEP_AUTH -eq 0 && -f "$BASIC_AUTH_FILE" ]]; then
  echo "[INFO] Removing basic auth file: $BASIC_AUTH_FILE"
  run_cmd rm -f "$BASIC_AUTH_FILE"
fi

# 6) Reload nginx if available
if command -v nginx >/dev/null 2>&1; then
  echo "[INFO] Reloading nginx (if config is valid)"
  if [[ $DRY_RUN -eq 0 ]]; then
    if nginx -t; then
      systemctl reload nginx || true
    else
      echo "[WARN] nginx -t failed; skipping reload."
    fi
  fi
fi

# 7) Optional purge of runtime dirs
if [[ $PURGE -eq 1 ]]; then
  for dir in "$SATURN_ROOT" "$WEB_ROOT" "$SATURN_STATE_DIR"; do
    if [[ -e "$dir" ]]; then
      echo "[INFO] Purging: $dir"
      run_cmd rm -rf "$dir"
    fi
  done
else
  echo "[INFO] Keeping runtime directories (default, or --no-purge): $SATURN_ROOT, $WEB_ROOT, $SATURN_STATE_DIR"
fi

# 8) Optional package cleanup
if [[ $REMOVE_PACKAGES -eq 1 ]]; then
  echo "[INFO] Removing install-time packages (best effort)"
  run_cmd apt-get remove --purge -y \
    nginx apache2-utils rustc cargo build-essential pkg-config python3-venv python3-psutil || true
  run_cmd apt-get autoremove -y || true
  run_cmd apt-get clean || true
fi

echo
echo "[SUMMARY]"
echo " Service disabled/removed: saturn-go.service"
echo " Watchdog disabled/removed: saturn-go-watchdog.service + saturn-go-watchdog.timer"
echo " NGINX site removed: $NGINX_SITE_AVAILABLE"
echo " NGINX SSE map removed: $NGINX_SSE_MAP"
if [[ $KEEP_AUTH -eq 0 ]]; then
  echo " Basic auth file removed: $BASIC_AUTH_FILE"
else
  echo " Basic auth file kept: $BASIC_AUTH_FILE"
fi
if [[ $PURGE -eq 1 ]]; then
  echo " Purged runtime dirs: $SATURN_ROOT, $WEB_ROOT, $SATURN_STATE_DIR"
else
  echo " Kept runtime dirs: $SATURN_ROOT, $WEB_ROOT, $SATURN_STATE_DIR"
fi
if [[ $REMOVE_PACKAGES -eq 1 ]]; then
  echo " Package cleanup attempted"
fi
echo "[OK] Uninstall complete."
