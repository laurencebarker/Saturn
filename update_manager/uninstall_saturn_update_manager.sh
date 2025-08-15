#!/usr/bin/env bash
# uninstall_saturn_update_manager.sh (Python-based), without touching ~/github/Saturn
# - Backs up removed files to ~/saturn-uninstall-backup-<timestamp>/
# - Cleans systemd unit, nginx/apache site, static UI, ~/.saturn, logs, desktop shortcut
# - Leaves ~/github/Saturn repo tree intact
# Flags:
#   --yes / -y           : non-interactive (assume "Yes")
#   --dry-run            : show what would be done, change nothing
#   --purge-backups      : also remove ~/saturn-backup-* and ~/pihpsdr-backup-* (after backing up)
#   --remove-venv        : remove ~/venv completely (after backing up)  [OFF by default]
#   --keep-logs          : keep ~/saturn-logs (default is remove)
#   --keep-runtime       : keep ~/.saturn (default is remove)

set -euo pipefail

YES=0
DRY=0
PURGE_BACKUPS=0
REMOVE_VENV=0
KEEP_LOGS=0
KEEP_RUNTIME=0

for arg in "$@"; do
  case "$arg" in
    --yes|-y) YES=1 ;;
    --dry-run) DRY=1 ;;
    --purge-backups) PURGE_BACKUPS=1 ;;
    --remove-venv) REMOVE_VENV=1 ;;
    --keep-logs) KEEP_LOGS=1 ;;
    --keep-runtime) KEEP_RUNTIME=1 ;;
    *) echo "Unknown flag: $arg" >&2; exit 2 ;;
  esac
done

# ----- Safety rails -----
REPO_DIR="$HOME/github/Saturn"
if [[ -d "$REPO_DIR" ]]; then
  echo "✅ Repo found and will NOT be touched: $REPO_DIR"
else
  echo "ℹ️ Repo directory not found at $REPO_DIR (that's fine)."
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/saturn-uninstall-backup-$timestamp"
mkdir -p "$BACKUP_DIR"

say() { printf "%s\n" "$*"; }
act() { if [[ $DRY -eq 1 ]]; then printf "[DRY] %s\n" "$*"; else eval "$@"; fi; }
backup_path() {
  # copy if the path exists
  local p="$1"
  if [[ -e "$p" ]]; then
    local dest="$BACKUP_DIR/backup$(echo "$p" | sed "s#^/#_root/#")"
    mkdir -p "$(dirname "$dest")"
    act "cp -a \"$p\" \"$dest\""
  fi
}

confirm() {
  [[ $YES -eq 1 ]] && return 0
  read -r -p "$1 [y/N]: " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

need_sudo() {
  if [[ $(id -u) -ne 0 ]]; then echo "sudo"; fi
}

# ----- Detect managers -----
SUDO="$(need_sudo || true)"

has_systemd() { command -v systemctl >/dev/null 2>&1; }
has_nginx()   { command -v nginx >/dev/null 2>&1; }
has_apache()  { command -v apache2ctl >/dev/null 2>&1 || command -v a2ensite >/dev/null 2>&1; }

# ----- Stop services/processes -----
say "==> Stopping services/processes…"

# Potential unit names (keep flexible)
CANDIDATE_UNITS=(
  "saturn-update-manager.service"
  "saturn_update_manager.service"
  "saturn-update-manager"
)

if has_systemd; then
  for u in "${CANDIDATE_UNITS[@]}"; do
    if $SUDO systemctl is-enabled "$u" >/dev/null 2>&1 || $SUDO systemctl is-active "$u" >/dev/null 2>&1; then
      say " • Disabling & stopping systemd unit: $u"
      act "$SUDO systemctl stop \"$u\" || true"
      act "$SUDO systemctl disable \"$u\" || true"
    fi
  done
fi

# Kill any stray gunicorn/flask serving Saturn
say " • Killing likely gunicorn/flask instances (safe best-effort)"
if [[ $DRY -eq 1 ]]; then
  echo "[DRY] pgrep -af 'gunicorn|saturn_update_manager|flask'"
else
  # shellcheck disable=SC2009
  ps -ef | grep -E 'gunicorn|saturn_update_manager|flask' | grep -v grep || true
  pids="$(pgrep -f 'gunicorn.*saturn|saturn_update_manager|flask.*saturn' || true)"
  if [[ -n "${pids:-}" ]]; then
    echo "$pids" | xargs -r $SUDO kill -TERM || true
    sleep 1
    echo "$pids" | xargs -r $SUDO kill -KILL || true
  fi
fi

# ----- Remove systemd unit file(s) -----
say "==> Removing systemd units (if present)…"
SYSTEMD_DIRS=(/etc/systemd/system /lib/systemd/system)
for d in "${SYSTEMD_DIRS[@]}"; do
  for u in "${CANDIDATE_UNITS[@]}"; do
    f="$d/$u"
    if [[ -f "$f" ]]; then
      say " • Found $f"
      backup_path "$f"
      act "$SUDO rm -f \"$f\""
    fi
  done
done
if has_systemd; then
  act "$SUDO systemctl daemon-reload"
fi

# ----- Web server cleanup -----
say "==> Web server cleanup…"

# NGINX site
if has_nginx; then
  NGINX_AVAIL="/etc/nginx/sites-available/saturn"
  NGINX_ENABLED="/etc/nginx/sites-enabled/saturn"
  if [[ -f "$NGINX_ENABLED" || -L "$NGINX_ENABLED" ]]; then
    say " • NGINX: unlink sites-enabled/saturn"
    backup_path "$NGINX_ENABLED"
    act "$SUDO rm -f \"$NGINX_ENABLED\""
  fi
  if [[ -f "$NGINX_AVAIL" ]]; then
    say " • NGINX: remove sites-available/saturn"
    backup_path "$NGINX_AVAIL"
    act "$SUDO rm -f \"$NGINX_AVAIL\""
  fi
  # try reload if nginx present
  act "$SUDO nginx -t >/dev/null 2>&1 && $SUDO systemctl reload nginx || true"
fi

# Apache site + htpasswd (back up the htpasswd; user may reuse elsewhere)
if has_apache; then
  APACHE_SITE_AVAIL="/etc/apache2/sites-available/saturn.conf"
  APACHE_SITE_ENABLED="/etc/apache2/sites-enabled/saturn.conf"
  HTPASSWD="/etc/apache2/.htpasswd"

  if [[ -f "$APACHE_SITE_ENABLED" || -L "$APACHE_SITE_ENABLED" ]]; then
    say " • Apache: remove sites-enabled/saturn.conf"
    backup_path "$APACHE_SITE_ENABLED"
    act "$SUDO rm -f \"$APACHE_SITE_ENABLED\""
  fi
  if [[ -f "$APACHE_SITE_AVAIL" ]]; then
    say " • Apache: remove sites-available/saturn.conf"
    backup_path "$APACHE_SITE_AVAIL"
    act "$SUDO rm -f \"$APACHE_SITE_AVAIL\""
  fi
  # If the site referenced HTPASSWD, we've backed it up; remove only if you want a clean slate
  if [[ -f "$HTPASSWD" ]]; then
    say " • Apache: (optional) removing /etc/apache2/.htpasswd (backed up)"
    backup_path "$HTPASSWD"
    act "$SUDO rm -f \"$HTPASSWD\""
  fi
  act "$SUDO apache2ctl configtest >/dev/null 2>&1 && $SUDO systemctl reload apache2 || true"
fi

# ----- Static UI paths that might have been installed -----
say "==> Removing installed static UI (if present)…"
STATIC_PATHS=(
  "/var/lib/saturn-web"
  "/var/www/html/saturn"
)

for p in "${STATIC_PATHS[@]}"; do
  if [[ -e "$p" ]]; then
    say " • Removing $p"
    backup_path "$p"
    act "$SUDO rm -rf \"$p\""
  fi
done

# ----- User-space runtime, logs, desktop shortcut -----
# Runtime
RUNTIME_DIR="$HOME/.saturn"
if [[ $KEEP_RUNTIME -eq 1 ]]; then
  say "==> Keeping runtime dir (requested): $RUNTIME_DIR"
else
  if [[ -d "$RUNTIME_DIR" ]]; then
    say "==> Removing runtime dir: $RUNTIME_DIR"
    backup_path "$RUNTIME_DIR"
    act "rm -rf \"$RUNTIME_DIR\""
  fi
fi

# Logs
LOG_DIR="$HOME/saturn-logs"
if [[ $KEEP_LOGS -eq 1 ]]; then
  say "==> Keeping logs (requested): $LOG_DIR"
else
  if [[ -d "$LOG_DIR" ]]; then
    say "==> Removing logs dir: $LOG_DIR"
    backup_path "$LOG_DIR"
    act "rm -rf \"$LOG_DIR\""
  fi
fi

# __pycache__ redirect folder used by the app
CACHE_DIR="$HOME/.cache/saturn-pycache"
if [[ -d "$CACHE_DIR" ]]; then
  say "==> Removing Python cache: $CACHE_DIR"
  backup_path "$CACHE_DIR"
  act "rm -rf \"$CACHE_DIR\""
fi

# Desktop shortcut
DESKTOP_FILE="$HOME/Desktop/SaturnUpdateManager.desktop"
if [[ -f "$DESKTOP_FILE" ]]; then
  say "==> Removing desktop shortcut: $DESKTOP_FILE"
  backup_path "$DESKTOP_FILE"
  act "rm -f \"$DESKTOP_FILE\""
fi

# ----- Optional: backups purge -----
if [[ $PURGE_BACKUPS -eq 1 ]]; then
  say "==> Purging user backup archives (saturn & pihpsdr) in ~/"
  shopt -s nullglob
  for b in "$HOME"/saturn-backup-* "$HOME"/pihpsdr-backup-*; do
    [[ -e "$b" ]] || continue
    say " • Removing $b"
    backup_path "$b"
    act "rm -rf \"$b\""
  done
  shopt -u nullglob
else
  say "==> Leaving your backup archives in place (use --purge-backups to remove)"
fi

# ----- Optional: remove venv -----
if [[ $REMOVE_VENV -eq 1 ]]; then
  VENV="$HOME/venv"
  if [[ -d "$VENV" ]]; then
    say "==> Removing virtualenv: $VENV"
    backup_path "$VENV"
    act "rm -rf \"$VENV\""
  fi
else
  say "==> Leaving your virtualenv in place (use --remove-venv to delete ~/venv)"
fi

# ----- Final confirmation -----
say ""
say "Backup of removed items stored in: $BACKUP_DIR"
say "✅ Uninstall steps completed."
if [[ $DRY -eq 1 ]]; then
  say "This was a DRY RUN. Re-run without --dry-run to make changes."
fi
