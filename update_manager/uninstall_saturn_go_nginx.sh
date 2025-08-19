#!/usr/bin/env bash
#
# uninstall_saturn_go_nginx.sh
# Removes Saturn Go + NGINX deployment and optionally its dependencies.
#
# Usage:
# sudo bash uninstall_saturn_go_nginx.sh [--purge] [--keep-auth] [--remove-packages] [--dry-run] [--yes]
#
set -euo pipefail
PURGE=0
KEEP_AUTH=0
REMOVE_PACKAGES=0
DRY_RUN=0
ASSUME_YES=0
for arg in "$@"; do
    case "$arg" in
        --purge) PURGE=1 ;;
        --keep-auth) KEEP_AUTH=1 ;;
        --remove-packages) REMOVE_PACKAGES=1 ;;
        --dry-run) DRY_RUN=1 ;;
        --yes) ASSUME_YES=1 ;;
        *) echo "[ERROR] Unknown argument: $arg" && exit 1 ;;
    esac
done
echo "This will uninstall the Saturn Go + NGINX deployment."
echo "Options: purge=$PURGE keep-auth=$KEEP_AUTH remove-packages=$REMOVE_PACKAGES dry-run=$DRY_RUN"
if [[ $ASSUME_YES -ne 1 ]]; then
    read -rp "Proceed? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "[INFO] Cancelled."; exit 0; }
fi
SYSTEMD_SERVICE="/etc/systemd/system/saturn-go.service"
NGINX_SITE_AVAILABLE="/etc/nginx/sites-available/saturn"
NGINX_SITE_ENABLED="/etc/nginx/sites-enabled/saturn"
BASIC_AUTH_FILE="/etc/nginx/.htpasswd"
SATURN_ROOT="/opt/saturn-go"
WEB_ROOT="/var/lib/saturn-web"
SATURN_HOME="$HOME/.saturn"
# 1. Stop and disable service
if systemctl list-units --full -all | grep -Fq "saturn-go.service"; then
    echo "[INFO] Stopping and disabling systemd service (saturn-go)..."
    [[ $DRY_RUN -eq 0 ]] && systemctl stop saturn-go && systemctl disable saturn-go
    echo "[OK] Service stopped/disabled"
fi
# 2. Kill leftover process
if lsof -i:8080 -t >/dev/null 2>&1; then
    PID=$(lsof -i:8080 -t)
    echo "[INFO] Killing leftover process on port 8080 (PID $PID)"
    [[ $DRY_RUN -eq 0 ]] && kill -9 "$PID"
else
    echo "[OK] No active listeners remain (or killed)."
fi
# 3. Remove systemd unit
if [[ -f "$SYSTEMD_SERVICE" ]]; then
    echo "[INFO] Removing systemd unit file: $SYSTEMD_SERVICE"
    [[ $DRY_RUN -eq 0 ]] && rm -f "$SYSTEMD_SERVICE" && systemctl daemon-reload
fi
# 4. Remove NGINX site config
if [[ -e "$NGINX_SITE_ENABLED" ]] || [[ -h "$NGINX_SITE_ENABLED" ]]; then
    echo "[INFO] Removing NGINX enabled site link: $NGINX_SITE_ENABLED"
    [[ $DRY_RUN -eq 0 ]] && rm -f "$NGINX_SITE_ENABLED"
fi
if [[ -f "$NGINX_SITE_AVAILABLE" ]]; then
    echo "[INFO] Removing NGINX site config: $NGINX_SITE_AVAILABLE"
    [[ $DRY_RUN -eq 0 ]] && rm -f "$NGINX_SITE_AVAILABLE"
fi
# 5. Remove basic auth (unless keep-auth)
if [[ $KEEP_AUTH -eq 0 && -f "$BASIC_AUTH_FILE" ]]; then
    echo "[INFO] Removing basic auth file: $BASIC_AUTH_FILE"
    [[ $DRY_RUN -eq 0 ]] && rm -f "$BASIC_AUTH_FILE"
fi
# 6. Reload NGINX
if command -v nginx >/dev/null; then
    echo "[INFO] Reloading NGINX..."
    if [[ $DRY_RUN -eq 0 ]]; then
        if nginx -t; then
            systemctl reload nginx
        else
            echo "[WARN] NGINX config test failed; skipping reload. Manual fix may be needed."
        fi
    fi
fi
# 7. Remove Saturn runtime files (purge option)
if [[ $PURGE -eq 1 ]]; then
    for dir in "$SATURN_ROOT" "$WEB_ROOT" "$SATURN_HOME"; do
        if [[ -d "$dir" ]]; then
            echo "[INFO] Purging directory: $dir"
            [[ $DRY_RUN -eq 0 ]] && rm -rf "$dir"
        fi
    done
fi
# 8. Remove basic packages (optional)
if [[ $REMOVE_PACKAGES -eq 1 ]]; then
    echo "[INFO] Removing system packages..."
    [[ $DRY_RUN -eq 0 ]] && apt-get remove --purge -y nginx apache2-utils golang-go python3 build-essential curl
    [[ $DRY_RUN -eq 0 ]] && apt-get autoremove -y && apt-get clean
fi
echo
echo "[SUMMARY]"
echo " Service file removed: $SYSTEMD_SERVICE"
echo " NGINX site removed: $NGINX_SITE_AVAILABLE (and enabled link)"
if [[ $KEEP_AUTH -eq 0 ]]; then
    echo " Basic auth file: $BASIC_AUTH_FILE (removed)"
else
    echo " Basic auth file: $BASIC_AUTH_FILE (kept)"
fi
if [[ $PURGE -eq 1 ]]; then
    echo " Saturn root: $SATURN_ROOT (removed)"
    echo " Web root: $WEB_ROOT (removed)"
    echo " Mirror dir: $SATURN_HOME (removed)"
fi
if [[ $REMOVE_PACKAGES -eq 1 ]]; then
    echo " System packages removed: nginx apache2-utils golang-go python3 build-essential curl"
fi
echo "[OK] Uninstall complete."
