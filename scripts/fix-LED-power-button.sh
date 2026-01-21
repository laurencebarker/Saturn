#!/usr/bin/env bash
# fix-LED-power-button.sh  (Bookworm & Trixie)
# Front-panel LED is on BCM15:
#   pinctrl set 15 op dh  -> RED
#   pinctrl set 15 op dl  -> WHITE
# This script:
#   1) (optionally) pins early-boot default to RED via config.txt
#   2) installs a systemd unit that sets RED at boot, WHITE on shutdown
# Logs under: journalctl -t fix-LED-power-button
#
# Env knobs:
#   EARLY_DEFAULT=0   # skip touching config.txt (default is 1)
#   SERVICE_NAME=gpio15-setup.service  # keep legacy name by default
# Written by: Jerry DeLong kd4yal

set -euo pipefail

SERVICE_NAME="${SERVICE_NAME:-gpio15-setup.service}"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"
EARLY_DEFAULT="${EARLY_DEFAULT:-1}"

log(){ echo "$1" | systemd-cat -t fix-LED-power-button; }

require_root() { if [ "$(id -u)" -ne 0 ]; then echo "Run with sudo." >&2; log "error: not root"; exit 1; fi; }
require_root

# ----- locate config.txt for Bookworm/Trixie -----
CONFIG_TXT="/boot/firmware/config.txt"
[ -f "$CONFIG_TXT" ] || CONFIG_TXT="/boot/config.txt"
if [ ! -f "$CONFIG_TXT" ]; then
  log "warning: no config.txt found at /boot/firmware or /boot (continuing without early default)"
  EARLY_DEFAULT=0
fi

# ----- ensure pinctrl exists (/usr/bin/pinctrl) -----
ensure_pinctrl() {
  if command -v pinctrl >/dev/null 2>&1; then
    log "pinctrl present at $(command -v pinctrl)"
    return 0
  fi
  log "pinctrl missing; building from raspberrypi/utils (this takes a minute)"
  apt-get update -y
  apt-get install -y --no-install-recommends git cmake build-essential device-tree-compiler libfdt-dev
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  git clone --depth=1 https://github.com/raspberrypi/utils "$tmpdir/utils"
  ( cd "$tmpdir/utils/pinctrl" && cmake . && make -j"$(nproc)" && make install )
  hash -r
  if ! command -v pinctrl >/dev/null 2>&1; then
    log "error: pinctrl install failed"
    exit 1
  fi
  log "pinctrl installed to $(command -v pinctrl)"
}
ensure_pinctrl

# ----- optional: set early-boot default so LED is RED before userspace -----
if [ "$EARLY_DEFAULT" = "1" ]; then
  if grep -Eq '^\s*gpio=15=' "$CONFIG_TXT"; then
    # normalize whatever was there to op,dh
    sed -i 's/^\s*gpio=15=.*/gpio=15=op,dh/' "$CONFIG_TXT"
    log "normalized existing gpio=15=… → gpio=15=op,dh in $(basename "$CONFIG_TXT")"
  else
    echo 'gpio=15=op,dh' >> "$CONFIG_TXT"
    log "appended gpio=15=op,dh to $(basename "$CONFIG_TXT")"
  fi
else
  log "EARLY_DEFAULT=0: leaving $(basename "$CONFIG_TXT") unchanged"
fi

# Don’t touch unrelated overlays (e.g., gpio-poweroff on 20/21) here.

# ----- install systemd unit: RED while up, WHITE on shutdown -----
cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=Set Saturn front-panel LED on BCM15 (dh=red, dl=white)
DefaultDependencies=yes
After=local-fs.target
Before=shutdown.target halt.target poweroff.target

[Service]
Type=oneshot
RemainAfterExit=yes
# RED for normal operation
ExecStart=/usr/bin/pinctrl set 15 op dh
# WHITE when we are going down
ExecStopPost=/usr/bin/pinctrl set 15 op dl

[Install]
WantedBy=multi-user.target
EOF
chmod 0644 "$SERVICE_FILE"
log "installed $SERVICE_FILE"

# ----- enable & start -----
systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME"

# ----- verify quickly -----
state="$(pinctrl get 15 || true)"
log "pinctrl get 15 → $state"

echo
echo "Done."
echo "• Early default set in: $CONFIG_TXT (gpio=15=op,dh)  [EARLY_DEFAULT=$EARLY_DEFAULT]"
echo "• Service: $SERVICE_NAME (RED on boot; WHITE on shutdown)"
echo "Check:  sudo systemctl status $SERVICE_NAME ; pinctrl get 15"
echo "If you want instant early RED from firmware, reboot once."
