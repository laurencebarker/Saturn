#!/usr/bin/env bash
set -euo pipefail

SATURN_ROOT="/opt/saturn-go"
BIN_DIR="$SATURN_ROOT/bin"
SCRIPTS_DIR="$SATURN_ROOT/scripts"
WEB_ROOT="/var/lib/saturn-web"
NGINX_SITE="/etc/nginx/sites-available/saturn"
NGINX_SITE_LINK="/etc/nginx/sites-enabled/saturn"
NGINX_SSE_MAP="/etc/nginx/conf.d/saturn_sse_map.conf"
BASIC_AUTH_FILE="/etc/nginx/.htpasswd"
SERVICE_FILE="/etc/systemd/system/saturn-go.service"
WATCHDOG_SCRIPT_NAME="saturn-health-watchdog.sh"
WATCHDOG_SERVICE_FILE="/etc/systemd/system/saturn-go-watchdog.service"
WATCHDOG_TIMER_FILE="/etc/systemd/system/saturn-go-watchdog.timer"
SOURCE_DIR="/home/${SUDO_USER:-$USER}/github/Saturn/update_manager"
RUST_SRC_DIR="$SOURCE_DIR/rust-server"

SATURN_ADDR="${SATURN_ADDR:-127.0.0.1:8080}"
SATURN_MAX_BODY_BYTES="${SATURN_MAX_BODY_BYTES:-2147483648}"
SATURN_RESTORE_MAX_UPLOAD_BYTES="${SATURN_RESTORE_MAX_UPLOAD_BYTES:-2147483648}"
SATURN_NGINX_CLIENT_MAX_BODY_SIZE="${SATURN_NGINX_CLIENT_MAX_BODY_SIZE:-2G}"
SATURN_STATE_DIR="${SATURN_STATE_DIR:-/var/lib/saturn-state}"
SATURN_REPO_ROOT_FILE="${SATURN_REPO_ROOT_FILE:-${SATURN_STATE_DIR}/repo_root.txt}"
SATURN_UPDATE_POLICY_FILE="${SATURN_UPDATE_POLICY_FILE:-${SATURN_STATE_DIR}/update_policy.json}"
SATURN_UPDATE_STATE_FILE="${SATURN_UPDATE_STATE_FILE:-${SATURN_STATE_DIR}/update_state.json}"
SATURN_SNAPSHOT_DIR="${SATURN_SNAPSHOT_DIR:-${SATURN_STATE_DIR}/snapshots}"
SATURN_STAGING_DIR="${SATURN_STAGING_DIR:-${SATURN_STATE_DIR}/repo-staging}"
SATURN_WATCHDOG_URL="${SATURN_WATCHDOG_URL:-http://${SATURN_ADDR}/healthz}"
SATURN_WATCHDOG_INTERVAL="${SATURN_WATCHDOG_INTERVAL:-30s}"

bold(){ printf "\e[1m%s\e[0m\n" "$*"; }
ok(){   printf "[OK] %s\n" "$*"; }
info(){ printf "[INFO] %s\n" "$*"; }
warn(){ printf "[WARN] %s\n" "$*"; }
err(){  printf "[ERR] %s\n" "$*" >&2; }

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  err "Run as root (sudo)."
  exit 1
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
  err "Source directory not found: $SOURCE_DIR"
  exit 1
fi
if [[ ! -f "$RUST_SRC_DIR/Cargo.toml" ]]; then
  err "Rust server source not found: $RUST_SRC_DIR"
  exit 1
fi

# Pick a non-root service user by default.
if [[ -n "${SATURN_SERVICE_USER:-}" ]]; then
  SERVICE_USER="$SATURN_SERVICE_USER"
elif [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
  SERVICE_USER="$SUDO_USER"
elif id -u pi >/dev/null 2>&1; then
  SERVICE_USER="pi"
else
  err "Set SATURN_SERVICE_USER to a valid non-root user."
  exit 1
fi
SERVICE_GROUP="${SATURN_SERVICE_GROUP:-$SERVICE_USER}"

if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
  err "Service user does not exist: $SERVICE_USER"
  exit 1
fi
if ! getent group "$SERVICE_GROUP" >/dev/null 2>&1; then
  err "Service group does not exist: $SERVICE_GROUP"
  exit 1
fi

SERVICE_HOME="$(getent passwd "$SERVICE_USER" | cut -d: -f6)"
if [[ -z "$SERVICE_HOME" || ! -d "$SERVICE_HOME" ]]; then
  err "Cannot resolve home directory for $SERVICE_USER"
  exit 1
fi
DEFAULT_REPO_ROOT="${SATURN_REPO_ROOT:-$SERVICE_HOME/github/Saturn}"

info "Installing dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
  nginx apache2-utils build-essential pkg-config \
  curl git rsync \
  python3 python3-venv python3-psutil \
  rustc cargo
ok "Dependencies installed"

info "Preparing runtime directories..."
mkdir -p "$BIN_DIR" "$SCRIPTS_DIR" "$WEB_ROOT" "$SATURN_STATE_DIR" "$SATURN_SNAPSHOT_DIR" "$SATURN_STAGING_DIR"
ok "Directories ready"

copy_web_asset () {
  local name="$1"
  local from_template="$SOURCE_DIR/templates/$name"
  local from_repo="$SOURCE_DIR/$name"
  if [[ -f "$from_template" ]]; then
    cp -f "$from_template" "$WEB_ROOT/$name"
  elif [[ -f "$from_repo" ]]; then
    cp -f "$from_repo" "$WEB_ROOT/$name"
  else
    err "Missing required web asset: $name"
    exit 1
  fi
}

info "Copying web assets..."
copy_web_asset "index.html"
copy_web_asset "monitor.html"
copy_web_asset "backup.html"

if [[ -f "$SOURCE_DIR/scripts/config.json" ]]; then
  cp -f "$SOURCE_DIR/scripts/config.json" "$WEB_ROOT/config.json"
elif [[ -f "$SOURCE_DIR/config.json" ]]; then
  cp -f "$SOURCE_DIR/config.json" "$WEB_ROOT/config.json"
else
  err "Missing config.json in source tree"
  exit 1
fi

if [[ -f "$SOURCE_DIR/scripts/themes.json" ]]; then
  cp -f "$SOURCE_DIR/scripts/themes.json" "$WEB_ROOT/themes.json"
elif [[ -f "$SOURCE_DIR/themes.json" ]]; then
  cp -f "$SOURCE_DIR/themes.json" "$WEB_ROOT/themes.json"
else
  err "Missing themes.json in source tree"
  exit 1
fi
ok "Web assets copied"

info "Copying scripts..."
find "$SCRIPTS_DIR" -mindepth 1 -maxdepth 1 -type f -delete || true
while IFS= read -r -d '' src; do
  cp -f "$src" "$SCRIPTS_DIR/"
done < <(find "$SOURCE_DIR/scripts" -maxdepth 1 -type f -print0)

cat >"$SCRIPTS_DIR/$WATCHDOG_SCRIPT_NAME" <<'WATCHDOG'
#!/usr/bin/env bash
set -euo pipefail

url="${SATURN_WATCHDOG_URL:-http://127.0.0.1:8080/healthz}"
service="${SATURN_WATCHDOG_SERVICE:-saturn-go.service}"
timeout="${SATURN_WATCHDOG_TIMEOUT:-4}"

if ! curl -fsS --max-time "$timeout" "$url" >/dev/null 2>&1; then
  logger -t saturn-watchdog "health check failed for $url; restarting $service"
  systemctl restart "$service" || true
fi
WATCHDOG
ok "Scripts copied"

info "Setting file permissions..."
chown -R root:root "$SATURN_ROOT" "$WEB_ROOT"
find "$WEB_ROOT" -type d -print0 | xargs -0 -r chmod 0755
find "$WEB_ROOT" -type f -print0 | xargs -0 -r chmod 0644
find "$SCRIPTS_DIR" -type d -print0 | xargs -0 -r chmod 0755
find "$SCRIPTS_DIR" -type f \( -name '*.sh' -o -name '*.py' \) -print0 | xargs -0 -r chmod 0755
find "$SCRIPTS_DIR" -type f ! \( -name '*.sh' -o -name '*.py' \) -print0 | xargs -0 -r chmod 0644
chmod 0755 "$SCRIPTS_DIR/$WATCHDOG_SCRIPT_NAME"
chown -R "$SERVICE_USER:$SERVICE_GROUP" "$SATURN_STATE_DIR"
find "$SATURN_STATE_DIR" -type d -print0 | xargs -0 -r chmod 0750
find "$SATURN_STATE_DIR" -type f -print0 | xargs -0 -r chmod 0640
ok "Permissions set"

info "Building Rust server..."
pushd "$RUST_SRC_DIR" >/dev/null
cargo build --release
cp -f target/release/saturn-go "$BIN_DIR/saturn-go"
popd >/dev/null
chmod 0755 "$BIN_DIR/saturn-go"
ok "Rust binary installed to $BIN_DIR/saturn-go"

if [[ ! -f "$SATURN_REPO_ROOT_FILE" ]]; then
  printf '%s\n' "$DEFAULT_REPO_ROOT" > "$SATURN_REPO_ROOT_FILE"
  chown "$SERVICE_USER:$SERVICE_GROUP" "$SATURN_REPO_ROOT_FILE"
  chmod 0640 "$SATURN_REPO_ROOT_FILE"
fi

info "Configuring nginx..."
cat >"$NGINX_SSE_MAP" <<'NGINX'
map $http_accept $is_sse {
  default               0;
  "~*text/event-stream" 1;
}
NGINX

cat >"$NGINX_SITE" <<NGINX
server {
  listen 80 default_server;
  server_name _;
  client_max_body_size ${SATURN_NGINX_CLIENT_MAX_BODY_SIZE};

  location = / {
    return 302 /saturn/;
  }

  location = /saturn/run {
    auth_basic "Restricted";
    auth_basic_user_file ${BASIC_AUTH_FILE};

    include /etc/nginx/proxy_params;
    proxy_pass http://${SATURN_ADDR}/run;

    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_read_timeout 1d;
    proxy_send_timeout 1d;
    proxy_buffering off;
    proxy_request_buffering off;
    proxy_cache off;
    gzip off;
    add_header X-Accel-Buffering no;
    add_header Cache-Control "no-cache";
  }

  location /saturn/ {
    auth_basic "Restricted";
    auth_basic_user_file ${BASIC_AUTH_FILE};

    include /etc/nginx/proxy_params;
    proxy_pass http://${SATURN_ADDR}/;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_read_timeout 300s;
  }
}
NGINX

PASSWORD_MIN_LEN=5
generated_password=""
if [[ ! -s "$BASIC_AUTH_FILE" ]]; then
  info "Creating HTTP basic auth credentials for admin user..."
  admin_password="${SATURN_ADMIN_PASSWORD:-}"
  if [[ -z "$admin_password" ]]; then
    if [[ -t 0 ]]; then
      while true; do
        read -r -s -p "Enter admin password (min ${PASSWORD_MIN_LEN} chars): " admin_password; echo
        read -r -s -p "Confirm admin password: " admin_password_confirm; echo
        if [[ "$admin_password" != "$admin_password_confirm" ]]; then
          warn "Passwords do not match. Try again."
          continue
        fi
        if [[ ${#admin_password} -lt ${PASSWORD_MIN_LEN} ]]; then
          warn "Password too short. Minimum ${PASSWORD_MIN_LEN} characters."
          continue
        fi
        break
      done
    else
      admin_password="$(tr -dc 'A-Za-z0-9@#%^+=_' </dev/urandom | head -c 24)"
      generated_password="$admin_password"
      warn "No TTY available; generated random admin password."
    fi
  fi
  if [[ ${#admin_password} -lt ${PASSWORD_MIN_LEN} ]]; then
    err "Provided SATURN_ADMIN_PASSWORD is too short (minimum ${PASSWORD_MIN_LEN} characters)."
    exit 1
  fi

  printf '%s\n' "$admin_password" | htpasswd -i -c "$BASIC_AUTH_FILE" admin >/dev/null
  chmod 0640 "$BASIC_AUTH_FILE"
  chown root:www-data "$BASIC_AUTH_FILE"
  ok "Basic auth configured"
else
  info "Reusing existing $BASIC_AUTH_FILE"
fi

rm -f /etc/nginx/sites-enabled/default || true
ln -sf "$NGINX_SITE" "$NGINX_SITE_LINK"

if ss -ltnp | grep -q ':80 ' && ss -ltnp | grep -qi apache2; then
  warn "Apache detected on port 80; stopping and disabling apache2"
  systemctl stop apache2 || true
  systemctl disable apache2 || true
fi

nginx -t
if systemctl is-active --quiet nginx; then
  systemctl reload nginx
else
  systemctl enable --now nginx
fi
ok "nginx configured"

info "Writing systemd unit..."
cat >"$SERVICE_FILE" <<SERVICE
[Unit]
Description=Saturn Update Manager (Rust backend)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=SATURN_WEBROOT=${WEB_ROOT}
Environment=SATURN_CONFIG=${WEB_ROOT}/config.json
Environment=SATURN_ADDR=${SATURN_ADDR}
Environment=SATURN_REPO_ROOT=${DEFAULT_REPO_ROOT}
Environment=SATURN_REPO_ROOT_FILE=${SATURN_REPO_ROOT_FILE}
Environment=SATURN_STATE_DIR=${SATURN_STATE_DIR}
Environment=SATURN_UPDATE_POLICY_FILE=${SATURN_UPDATE_POLICY_FILE}
Environment=SATURN_UPDATE_STATE_FILE=${SATURN_UPDATE_STATE_FILE}
Environment=SATURN_SNAPSHOT_DIR=${SATURN_SNAPSHOT_DIR}
Environment=SATURN_STAGING_DIR=${SATURN_STAGING_DIR}
Environment=SATURN_MAX_BODY_BYTES=${SATURN_MAX_BODY_BYTES}
Environment=SATURN_RESTORE_MAX_UPLOAD_BYTES=${SATURN_RESTORE_MAX_UPLOAD_BYTES}
Environment=PYTHONUNBUFFERED=1
ExecStart=${BIN_DIR}/saturn-go
WorkingDirectory=${SATURN_ROOT}
User=${SERVICE_USER}
Group=${SERVICE_GROUP}
Restart=on-failure
RestartSec=2
PrivateTmp=true
RestrictSUIDSGID=true
LockPersonality=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
ProtectClock=true
SystemCallArchitectures=native
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
SERVICE

cat >"$WATCHDOG_SERVICE_FILE" <<WATCHDOG_SERVICE
[Unit]
Description=Saturn Update Manager Health Watchdog
After=network-online.target saturn-go.service
Wants=network-online.target

[Service]
Type=oneshot
Environment=SATURN_WATCHDOG_URL=${SATURN_WATCHDOG_URL}
Environment=SATURN_WATCHDOG_SERVICE=saturn-go.service
Environment=SATURN_WATCHDOG_TIMEOUT=4
ExecStart=${SCRIPTS_DIR}/${WATCHDOG_SCRIPT_NAME}
WATCHDOG_SERVICE

cat >"$WATCHDOG_TIMER_FILE" <<WATCHDOG_TIMER
[Unit]
Description=Run Saturn health watchdog

[Timer]
OnBootSec=45s
OnUnitActiveSec=${SATURN_WATCHDOG_INTERVAL}
AccuracySec=1s
Persistent=true
Unit=saturn-go-watchdog.service

[Install]
WantedBy=timers.target
WATCHDOG_TIMER

systemctl daemon-reload
systemctl enable saturn-go.service
systemctl enable saturn-go-watchdog.timer
if systemctl is-active --quiet saturn-go.service; then
  systemctl restart saturn-go.service
else
  systemctl start saturn-go.service
fi
if systemctl is-active --quiet saturn-go-watchdog.timer; then
  systemctl restart saturn-go-watchdog.timer
else
  systemctl start saturn-go-watchdog.timer
fi
ok "Service and watchdog enabled and restarted"

info "Waiting for backend health endpoint..."
healthy=0
for _ in {1..40}; do
  if curl -fsS "http://${SATURN_ADDR}/healthz" >/dev/null 2>&1; then
    healthy=1
    ok "Backend is healthy"
    break
  fi
  sleep 0.25
done
if [[ $healthy -ne 1 ]]; then
  err "Backend health check failed at http://${SATURN_ADDR}/healthz"
  echo "[INFO] saturn-go.service status:"
  systemctl --no-pager --full status saturn-go.service || true
  echo "[INFO] Recent saturn-go.service logs:"
  journalctl -u saturn-go.service -n 40 --no-pager || true
  exit 1
fi

bold "[SUMMARY]"
echo " Web UI:   http://<host>/saturn/"
echo " API base: http://<host>/saturn/"
echo " Binary:   ${BIN_DIR}/saturn-go"
echo " Service:  saturn-go.service (user=${SERVICE_USER})"
echo " Watchdog: saturn-go-watchdog.timer (${SATURN_WATCHDOG_INTERVAL})"
echo " Repo root default: ${DEFAULT_REPO_ROOT}"
if [[ -n "$generated_password" ]]; then
  echo " Admin user: admin"
  echo " Generated password: ${generated_password}"
  warn "Store this password now and change it after first login."
fi
ok "Install complete."
