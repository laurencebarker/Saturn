#!/bin/bash
# fix-LED-power-button.sh (Trixie-safe)
# Set the on-board Power LED via the kernel LED class (no GPIO poking).
# Works on older images (led0/led1) and newer (ACT/PWR).
# Logs to journalctl as 'fix-LED-power-button'.
# Written by: Jerry DeLong KD4YAL

set -euo pipefail

SERVICE_FILE="/etc/systemd/system/pwr-led-setup.service"
HELPER="/usr/local/sbin/pwr-led-setup.sh"

log(){ echo "$1" | systemd-cat -t fix-LED-power-button; }

# Must be root
if [ "$(id -u)" -ne 0 ]; then
  log "Error: run with sudo."
  echo "Run with sudo." >&2
  exit 1
fi

# Discover LED class paths (prefer new names, fall back to old)
find_led(){
  local wanted_alt="$1" wanted_legacy="$2"
  if [ -d "/sys/class/leds/$wanted_alt" ]; then
    echo "/sys/class/leds/$wanted_alt"
  elif [ -d "/sys/devices/platform/leds/leds/$wanted_alt" ]; then
    echo "/sys/devices/platform/leds/leds/$wanted_alt"
  elif [ -d "/sys/class/leds/$wanted_legacy" ]; then
    echo "/sys/class/leds/$wanted_legacy"
  else
    echo ""
  fi
}

PWR_DIR="$(find_led PWR led1)"
ACT_DIR="$(find_led ACT led0)"

if [ -z "$PWR_DIR" ]; then
  log "Warning: No PWR LED found under /sys/class/leds (this model/OS may not expose it)."
else
  log "Detected PWR LED at $PWR_DIR"
fi

if [ -n "$ACT_DIR" ]; then
  log "Detected ACT LED at $ACT_DIR"
fi

# Write the helper that actually nudges the LEDs at boot
cat > "$HELPER" <<'EOSH'
#!/usr/bin/env bash
set -eu

log(){ echo "$1" | systemd-cat -t pwr-led-setup; }

PWR_DIR=""
ACT_DIR=""

# Re-discover at runtime (paths may differ across boards)
if   [ -d /sys/class/leds/PWR ]; then PWR_DIR=/sys/class/leds/PWR
elif [ -d /sys/devices/platform/leds/leds/PWR ]; then PWR_DIR=/sys/devices/platform/leds/leds/PWR
elif [ -d /sys/class/leds/led1 ]; then PWR_DIR=/sys/class/leds/led1
fi

if   [ -d /sys/class/leds/ACT ]; then ACT_DIR=/sys/class/leds/ACT
elif [ -d /sys/devices/platform/leds/leds/ACT ]; then ACT_DIR=/sys/devices/platform/leds/leds/ACT
elif [ -d /sys/class/leds/led0 ]; then ACT_DIR=/sys/class/leds/led0
fi

# ---- Power LED policy ----
# Keep PWR on (stable) using the 'default-on' trigger.
if [ -n "$PWR_DIR" ]; then
  if [ -w "$PWR_DIR/trigger" ]; then
    echo default-on > "$PWR_DIR/trigger" || true
    log "PWR: set trigger=default-on"
  elif [ -w "$PWR_DIR/brightness" ]; then
    # Fallback: manual brightness (driver handles polarity)
    echo 1 > "$PWR_DIR/brightness" || true
    log "PWR: set brightness=1"
  else
    log "PWR: no writable trigger/brightness"
  fi
else
  log "PWR: not present on this system"
fi

# ---- Activity LED (optional) ----
# To force ACT steady on:
#   [ -n "$ACT_DIR" ] && echo default-on > "$ACT_DIR/trigger" || true
# To turn ACT fully off:
#   [ -n "$ACT_DIR" ] && { echo none > "$ACT_DIR/trigger"; echo 0 > "$ACT_DIR/brightness"; } || true
# To set ACT to SD activity:
#   [ -n "$ACT_DIR" ] && echo mmc0 > "$ACT_DIR/trigger" || true

exit 0
EOSH
chmod 755 "$HELPER"
log "Installed helper at $HELPER"

# Create the oneshot service that calls the helper at boot
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Configure on-board Power LED (kernel LED class)
After=multi-user.target
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=$HELPER
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
chmod 644 "$SERVICE_FILE"
log "Created $SERVICE_FILE"

# Make sure old GPIO hacks aren't fighting us
if grep -Eq '^\s*gpio=15=' /boot/config.txt; then
  sed -i 's/^\s*gpio=15=.*/# (disabled by fix-LED-power-button) &/' /boot/config.txt
  log "Commented out legacy gpio=15=… in /boot/config.txt to avoid conflicts"
fi

# Enable + start
systemctl daemon-reload
systemctl enable --now pwr-led-setup.service

# Quick verification
if [ -n "$PWR_DIR" ]; then
  trig=$(cat "$PWR_DIR/trigger" 2>/dev/null || echo "?")
  bright=$(cat "$PWR_DIR/brightness" 2>/dev/null || echo "?")
  log "PWR: trigger=$trig brightness=$bright"
fi

echo "Done. Check logs with: journalctl -u pwr-led-setup.service -b"
