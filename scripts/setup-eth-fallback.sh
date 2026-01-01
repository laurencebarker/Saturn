#!/bin/bash
# setup-eth-fallback.sh - enabling automatic IPv4 link-local (APIPA) fallback (Bookworm + Trixie)
# Version: 2.4
# Written by: Jerry DeLong, KD4YAL
# Date: 2026-01-01
#
## Setup-Eth-Fallback.sh Script Documentation
##
## Purpose / Problem Being Solved
## ------------------------------
## Raspberry Pi OS Bookworm switched the default network stack away from dhcpcd toward
## NetworkManager (and in newer images, often via Netplan/cloud-init feeding NetworkManager).
## On many installs this change results in *no reliable IPv4 link-local fallback* (APIPA, 169.254/16)
## when no DHCP server is present.
##
## Why this matters for SDR users:
## - Some users connect a Raspberry Pi directly to a Windows PC running Thetis (or connect off-network),
##   meaning there may be *no DHCP server* available.
## - If the Pi never self-assigns a 169.254.x.x address, the PC also may not get a usable peer route,
##   and the user can’t connect/control the radio as intended.
##
## Raspberry Pi OS Trixie status:
## - It was widely expected that IPv4 link-local behavior would be “fixed” in Trixie.
## - Reports still indicate some cases where IPv4LL/APIPA is not assigned properly, depending on
##   configuration and how NetworkManager is provisioned.
##
## What This Script Does (High Level)
## ----------------------------------
## This script is designed as a “one-and-done” fix that:
## 1) Ensures required packages are installed (NetworkManager, iproute2, and arping if available)
## 2) Creates *persistent* NetworkManager connection profiles for a given Ethernet interface (default eth0):
##    - <iface>-dhcp         : Primary profile. Attempts DHCP quickly.
##                             On newer NetworkManager versions (>= 1.52), it also sets:
##                               ipv4.link-local=fallback
##                             which means: "Use DHCP first, but if DHCP fails, fall back to IPv4LL."
##    - <iface>-ll           : Explicit IPv4 link-local profile (ipv4.method=link-local).
##                             Used as a forced fallback on older NetworkManager builds or if DHCP stalls.
##    - <iface>-apipa-manual : Final “hard fallback” profile that assigns a deterministic 169.254.x.y/16
##                             address derived from the interface MAC (and uses ARP duplicate-address
##                             detection when arping is present).
##
## 3) Installs a lightweight monitor daemon (systemd service) that:
##    - Watches for carrier (link) on the interface
##    - Checks for presence of any IPv4 address (robust detection; ignores tentative/dadfailed)
##    - If no IPv4 is present after a grace period:
##        a) forces the DHCP profile up
##        b) if still no IPv4, forces the link-local profile up
##        c) if still no IPv4 (indicating IPv4LL may be broken), forces the manual APIPA profile up
##    - Adds DEBUG logging of the raw `ip -o -4 addr show` output when it believes IPv4 is missing
##
## 4) Performs validation at the end including:
##    - Confirms the correct active connection bound to the interface
##    - Confirms ipv4.link-local is truly set to fallback when supported (NM >= 1.52)
##      (NOTE: nmcli may show fallback as enum "4")
##    - Confirms an IPv4 address is present (DHCP or 169.254/16)
##
## IMPORTANT FIX (v2.3+)
## ---------------------
## NetworkManager allows multiple connections with the same ID if UUIDs differ.
## Earlier versions regenerated UUIDs on every run, creating duplicates like:
##   eth0-dhcp (uuid A) and eth0-dhcp (uuid B)
## Then nmcli outputs multiple blocks and multiple values (e.g. 4 and 0).
##
## v2.3+ reuses the UUID from the existing profile file (if present) and removes duplicates,
## ensuring only ONE eth0-dhcp / eth0-ll / eth0-apipa-manual exists at a time.
#
# ------------------------------------------------------------------------------

set -euo pipefail

# ----------------------------
# Pretty colors
# ----------------------------
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"

log()  { echo -e "${CYAN}[$(date '+%F %T')]${RESET} $*"; }
ok()   { echo -e "${GREEN}$*${RESET}"; }
warn() { echo -e "${YELLOW}$*${RESET}"; }
die()  { echo -e "${RED}ERROR:${RESET} $*" >&2; exit 1; }

# ----------------------------
# Args / defaults
# ----------------------------
INTERFACE="${1:-eth0}"

CON_DIR="/etc/NetworkManager/system-connections"
DHCP_CON="${INTERFACE}-dhcp"
LL_CON="${INTERFACE}-ll"
APIPA_CON="${INTERFACE}-apipa-manual"

DHCP_PROFILE="${CON_DIR}/${DHCP_CON}.nmconnection"
LL_PROFILE="${CON_DIR}/${LL_CON}.nmconnection"
APIPA_PROFILE="${CON_DIR}/${APIPA_CON}.nmconnection"

MONITOR_SCRIPT="/usr/local/bin/network-fallback-monitor.sh"
SERVICE_FILE="/etc/systemd/system/network-fallback.service"

CHECK_INTERVAL=20           # seconds between checks
NO_IP_GRACE=25              # seconds after carrier before we start forcing fallback actions
DHCP_TIMEOUT=6              # DHCP transaction timeout seconds (NM property)
FALLBACK_WAIT=6             # wait after switching profiles

# ----------------------------
# Root check
# ----------------------------
[[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run as root: sudo bash $0 ${INTERFACE}"

# ----------------------------
# Helpers
# ----------------------------
have_cmd() { command -v "$1" >/dev/null 2>&1; }

gen_uuid() { cat /proc/sys/kernel/random/uuid; }

get_uuid_from_profile() {
  local file="$1"
  if [[ -f "$file" ]]; then
    awk -F= '/^uuid=/{print $2; exit}' "$file" | tr -d '\r'
  fi
}

dedupe_nm_connections() {
  local name="$1"
  local keep_uuid="$2"

  mapfile -t uuids < <(nmcli -t -f NAME,UUID con show | awk -F: -v n="$name" '$1==n{print $2}')

  if ((${#uuids[@]} <= 1)); then
    return 0
  fi

  warn "Detected duplicate NM connections named '$name' (${#uuids[@]} entries). Cleaning up..."
  for u in "${uuids[@]}"; do
    if [[ "$u" != "$keep_uuid" ]]; then
      log "Deleting duplicate: $name (uuid $u)"
      nmcli -w 10 con delete "$u" >/dev/null 2>&1 || true
    fi
  done
}

apipa_from_mac() {
  local mac b5 b6 x y
  mac="$(cat "/sys/class/net/${INTERFACE}/address" | tr -d ':' | tr '[:lower:]' '[:upper:]')"
  b5="${mac:8:2}"
  b6="${mac:10:2}"
  x=$(( (16#${b5} % 254) + 1 ))
  y=$(( (16#${b6} % 254) + 1 ))
  echo "169.254.${x}.${y}"
}

# ----------------------------
# OS info (for logging only)
# ----------------------------
OS_CODENAME="unknown"
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_CODENAME="${VERSION_CODENAME:-unknown}"
fi
log "Target interface: ${INTERFACE}"
log "Detected OS codename: ${OS_CODENAME}"

# ----------------------------
# Dependencies
# ----------------------------
need_pkgs=()

have_cmd nmcli || need_pkgs+=(network-manager)
have_cmd ip    || need_pkgs+=(iproute2)
have_cmd arping || need_pkgs+=(iputils-arping)

if ((${#need_pkgs[@]})); then
  warn "Installing missing packages: ${need_pkgs[*]}"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y "${need_pkgs[@]}"
else
  ok "Dependencies look good (nmcli/ip present; arping: yes)."
fi

# ----------------------------
# Ensure NetworkManager is running
# ----------------------------
systemctl enable --now NetworkManager >/dev/null 2>&1 || true
systemctl is-active --quiet NetworkManager || die "NetworkManager is not active."

[[ -d "/sys/class/net/${INTERFACE}" ]] || die "Interface ${INTERFACE} not found."

mkdir -p "$CON_DIR"
chmod 700 "$CON_DIR"

# ----------------------------
# Detect NM version (for ipv4.link-local=fallback support)
# ----------------------------
NM_VERSION="$(nmcli -t -g VERSION general 2>/dev/null || true)"
log "NetworkManager version: ${NM_VERSION:-unknown}"

SUPPORTS_LL_FALLBACK="no"
if [[ -n "${NM_VERSION}" ]] && dpkg --compare-versions "${NM_VERSION}" ge "1.52"; then
  SUPPORTS_LL_FALLBACK="yes"
fi
log "Supports ipv4.link-local=fallback: ${SUPPORTS_LL_FALLBACK}"

# ----------------------------
# UUID strategy (reuse existing, else generate)
# ----------------------------
UUID_DHCP="$(get_uuid_from_profile "$DHCP_PROFILE")"
UUID_LL="$(get_uuid_from_profile "$LL_PROFILE")"
UUID_APIPA="$(get_uuid_from_profile "$APIPA_PROFILE")"

[[ -n "$UUID_DHCP"  ]] || UUID_DHCP="$(gen_uuid)"
[[ -n "$UUID_LL"    ]] || UUID_LL="$(gen_uuid)"
[[ -n "$UUID_APIPA" ]] || UUID_APIPA="$(gen_uuid)"

APIPA_ADDR="$(apipa_from_mac)"

# ----------------------------
# Write profiles (persistent)
# ----------------------------
log "Writing NetworkManager profiles into ${CON_DIR} (persistent storage)."

cat > "$DHCP_PROFILE" <<EOF
[connection]
id=${DHCP_CON}
uuid=${UUID_DHCP}
type=ethernet
interface-name=${INTERFACE}
autoconnect=true
autoconnect-priority=999
autoconnect-retries=2

[ethernet]

[ipv4]
method=auto
dhcp-timeout=${DHCP_TIMEOUT}
EOF

if [[ "$SUPPORTS_LL_FALLBACK" == "yes" ]]; then
  echo "link-local=fallback" >> "$DHCP_PROFILE"
fi

cat >> "$DHCP_PROFILE" <<'EOF'

[ipv6]
method=auto

[proxy]
EOF

cat > "$LL_PROFILE" <<EOF
[connection]
id=${LL_CON}
uuid=${UUID_LL}
type=ethernet
interface-name=${INTERFACE}
autoconnect=true
autoconnect-priority=500

[ethernet]

[ipv4]
method=link-local

[ipv6]
method=auto

[proxy]
EOF

cat > "$APIPA_PROFILE" <<EOF
[connection]
id=${APIPA_CON}
uuid=${UUID_APIPA}
type=ethernet
interface-name=${INTERFACE}
autoconnect=false
autoconnect-priority=10

[ethernet]

[ipv4]
method=manual
addresses=${APIPA_ADDR}/16
never-default=true

[ipv6]
method=ignore

[proxy]
EOF

chmod 600 "$DHCP_PROFILE" "$LL_PROFILE" "$APIPA_PROFILE"
chown root:root "$DHCP_PROFILE" "$LL_PROFILE" "$APIPA_PROFILE"

nmcli con reload

dedupe_nm_connections "$DHCP_CON" "$UUID_DHCP"
dedupe_nm_connections "$LL_CON" "$UUID_LL"
dedupe_nm_connections "$APIPA_CON" "$UUID_APIPA"

if [[ "$SUPPORTS_LL_FALLBACK" == "yes" ]]; then
  log "Forcing ipv4.link-local=fallback on ${DHCP_CON} (uuid ${UUID_DHCP}) via nmcli..."
  nmcli con modify "$UUID_DHCP" ipv4.link-local fallback >/dev/null 2>&1 || true
fi

ok "Profiles written:"
echo "  - ${DHCP_PROFILE} (uuid ${UUID_DHCP})"
echo "  - ${LL_PROFILE} (uuid ${UUID_LL})"
echo "  - ${APIPA_PROFILE} (uuid ${UUID_APIPA})"

# ----------------------------
# Monitor script (DROP-IN IMPROVED)
# ----------------------------
log "Installing monitor script: ${MONITOR_SCRIPT}"

cat > "$MONITOR_SCRIPT" <<EOF
#!/bin/bash
# network-fallback-monitor.sh
#
# Background watchdog that ensures the target interface always winds up with an IPv4 address:
# - Prefers DHCP (normal network)
# - Falls back to IPv4 link-local (169.254/16) if no DHCP exists
# - If IPv4LL fails, assigns a manual APIPA as a last resort
#
# v2.4 improvements:
# - More robust IPv4 detection (ignores tentative/dadfailed states)
# - DEBUG log of raw \`ip -o -4 addr show\` when it believes IPv4 is missing

set -euo pipefail

INTERFACE="${INTERFACE}"
DHCP_CON="${DHCP_CON}"
LL_CON="${LL_CON}"
APIPA_CON="${APIPA_CON}"

CHECK_INTERVAL=${CHECK_INTERVAL}
NO_IP_GRACE=${NO_IP_GRACE}
FALLBACK_WAIT=${FALLBACK_WAIT}

log() { echo "[\$(date '+%F %T')] \$*"; }

carrier_up() {
  [[ -r "/sys/class/net/\${INTERFACE}/carrier" ]] && [[ "\$(cat "/sys/class/net/\${INTERFACE}/carrier")" == "1" ]]
}

ipv4_present() {
  # Require a non-tentative, non-dadfailed IPv4 address
  ip -o -4 addr show dev "\${INTERFACE}" 2>/dev/null | grep -vqE '\\s(tentative|dadfailed)\\b' && \\
  ip -o -4 addr show dev "\${INTERFACE}" 2>/dev/null | grep -qE '\\sinet\\s[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]+\\b'
}

get_ipv4_list() {
  # Print "<addr/cidr> <last-field>" so we can see flags like noprefixroute/tentative if present
  ip -o -4 addr show dev "\${INTERFACE}" 2>/dev/null | awk '{print \$4, \$NF}' || true
}

debug_ip_dump() {
  local dump
  dump="\$(ip -o -4 addr show dev "\${INTERFACE}" 2>/dev/null | tr '\\n' ' ' || true)"
  [[ -n "\$dump" ]] || dump="none"
  log "DEBUG: ip -o -4 addr show dev \${INTERFACE}: \$dump"
}

pick_apipa_from_mac() {
  local mac b5 b6 x y
  mac="\$(cat "/sys/class/net/\${INTERFACE}/address" | tr -d ':' | tr '[:lower:]' '[:upper:]')"
  b5="\${mac:8:2}"
  b6="\${mac:10:2}"
  x=\$(( (16#\${b5} % 254) + 1 ))
  y=\$(( (16#\${b6} % 254) + 1 ))
  echo "169.254.\${x}.\${y}"
}

dad_ok_or_skip() {
  local ip="\$1"
  if command -v arping >/dev/null 2>&1; then
    arping -D -I "\${INTERFACE}" -c 2 "\${ip}" >/dev/null 2>&1
    return \$?
  fi
  return 0
}

ensure_up() {
  ip link set dev "\${INTERFACE}" up >/dev/null 2>&1 || true
}

last_carrier_state="0"
carrier_up_since=0

while true; do
  sleep "\${CHECK_INTERVAL}"

  if carrier_up; then
    if [[ "\${last_carrier_state}" != "1" ]]; then
      last_carrier_state="1"
      carrier_up_since=\$(date +%s)
      log "Carrier UP on \${INTERFACE}"
    fi
  else
    if [[ "\${last_carrier_state}" != "0" ]]; then
      last_carrier_state="0"
      carrier_up_since=0
      log "Carrier DOWN on \${INTERFACE}"
    fi
    continue
  fi

  ensure_up

  if ipv4_present; then
    log "IPv4 present on \${INTERFACE}: \$(get_ipv4_list | tr '\\n' ' ')"
    continue
  fi

  # Capture raw state whenever we think IPv4 is missing
  debug_ip_dump

  now=\$(date +%s)
  if (( carrier_up_since > 0 )) && (( now - carrier_up_since < NO_IP_GRACE )); then
    log "No IPv4 yet on \${INTERFACE}, within grace period (\$((NO_IP_GRACE - (now - carrier_up_since)))s)."
    continue
  fi

  log "No IPv4 on \${INTERFACE}. Forcing DHCP profile: \${DHCP_CON}"
  nmcli -w 10 con up "\${DHCP_CON}" >/dev/null 2>&1 || true
  sleep "\${FALLBACK_WAIT}"

  if ipv4_present; then
    log "IPv4 acquired after DHCP attempt: \$(get_ipv4_list | tr '\\n' ' ')"
    continue
  fi

  debug_ip_dump
  log "Still no IPv4. Forcing link-local profile: \${LL_CON}"
  nmcli -w 10 con up "\${LL_CON}" >/dev/null 2>&1 || true
  sleep "\${FALLBACK_WAIT}"

  if ipv4_present; then
    log "IPv4 acquired after link-local profile: \$(get_ipv4_list | tr '\\n' ' ')"
    continue
  fi

  debug_ip_dump
  cand="\$(pick_apipa_from_mac)"
  ip="\${cand}"

  if ! dad_ok_or_skip "\${ip}"; then
    log "DAD conflict on \${ip}. Searching for a free APIPA..."
    for i in \$(seq 1 20); do
      a=\$(( (RANDOM % 254) + 1 ))
      b=\$(( (RANDOM % 254) + 1 ))
      ip="169.254.\${a}.\${b}"
      if dad_ok_or_skip "\${ip}"; then
        break
      fi
    done
  fi

  log "Forcing manual APIPA profile: \${APIPA_CON} with \${ip}/16"
  nmcli con modify "\${APIPA_CON}" ipv4.addresses "\${ip}/16" ipv4.method manual ipv4.never-default yes >/dev/null 2>&1 || true
  nmcli -w 10 con up "\${APIPA_CON}" >/dev/null 2>&1 || true
  sleep "\${FALLBACK_WAIT}"

  if ipv4_present; then
    log "Manual APIPA success: \$(get_ipv4_list | tr '\\n' ' ')"
  else
    debug_ip_dump
    log "CRITICAL: still no IPv4 on \${INTERFACE}. Check: journalctl -u NetworkManager -u network-fallback"
  fi
done
EOF

chmod 755 "$MONITOR_SCRIPT"
chown root:root "$MONITOR_SCRIPT"

# ----------------------------
# systemd service
# ----------------------------
log "Installing systemd service: ${SERVICE_FILE}"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Network Fallback Monitor Service (DHCP -> IPv4LL -> Manual APIPA)
Wants=NetworkManager.service
After=NetworkManager.service

[Service]
Type=simple
ExecStart=${MONITOR_SCRIPT}
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now network-fallback.service >/dev/null 2>&1 || true
ok "network-fallback.service enabled + started."

# ----------------------------
# Validation (UUID-based)
# ----------------------------
warn "Validation: bringing up ${DHCP_CON} and verifying settings..."

log "Active connections before validation:"
nmcli -t -f NAME,DEVICE,TYPE con show --active || true

nmcli con down "${LL_CON}" >/dev/null 2>&1 || true
nmcli con down "${APIPA_CON}" >/dev/null 2>&1 || true

nmcli -w 10 con up "${UUID_DHCP}" >/dev/null 2>&1 || true
sleep 5

ACTIVE_ON_IFACE="$(nmcli -t -f NAME,DEVICE con show --active | awk -F: -v dev="$INTERFACE" '$2==dev{print $1}' | head -n1 || true)"
if [[ -n "$ACTIVE_ON_IFACE" ]]; then
  ok "Active connection bound to ${INTERFACE}: ${ACTIVE_ON_IFACE}"
else
  warn "No active NM connection currently bound to ${INTERFACE} (can happen briefly during transitions)."
fi

log "NM view of ${DHCP_CON} (uuid ${UUID_DHCP}) IPv4 settings:"
nmcli -f ipv4.method,ipv4.link-local,ipv4.dhcp-timeout con show "${UUID_DHCP}" || true

if [[ "$SUPPORTS_LL_FALLBACK" == "yes" ]]; then
  LL_MODE_RAW="$(nmcli -g ipv4.link-local con show "${UUID_DHCP}" 2>/dev/null | tr -d '\r' | awk 'NF{print; exit}')"
  case "$LL_MODE_RAW" in
    fallback|4)
      ok "ipv4.link-local reports fallback (raw value: '${LL_MODE_RAW}')."
      ;;
    *)
      warn "ipv4.link-local is not reporting fallback (raw: '${LL_MODE_RAW:-unknown}'). Re-applying..."
      nmcli con modify "${UUID_DHCP}" ipv4.link-local fallback >/dev/null 2>&1 || true
      nmcli -w 10 con up "${UUID_DHCP}" >/dev/null 2>&1 || true
      LL_MODE_RAW2="$(nmcli -g ipv4.link-local con show "${UUID_DHCP}" 2>/dev/null | tr -d '\r' | awk 'NF{print; exit}')"
      case "$LL_MODE_RAW2" in
        fallback|4) ok "ipv4.link-local now reports fallback (raw value: '${LL_MODE_RAW2}')." ;;
        *) warn "Still not reporting fallback (raw: '${LL_MODE_RAW2:-unknown}'). Monitor still protects users via ${LL_CON}/${APIPA_CON}." ;;
      esac
      ;;
  esac
fi

sleep 5
IP_LIST="$(ip -o -4 addr show dev "$INTERFACE" | awk '{print $4}' || true)"

if [[ -n "$IP_LIST" ]]; then
  ok "Validation: IPv4 present on ${INTERFACE}: ${IP_LIST}"
  if echo "$IP_LIST" | grep -q '^169\.254\.'; then
    warn "Note: link-local/APIPA address is active (expected on direct-connect/no-DHCP)."
  else
    ok "Note: DHCP (non-169.254) address appears active."
  fi
else
  warn "Validation: no IPv4 yet on ${INTERFACE}. Forcing link-local profile for immediate recovery..."
  nmcli -w 10 con up "${UUID_LL}" >/dev/null 2>&1 || true
  sleep 5
  IP_LIST2="$(ip -o -4 addr show dev "$INTERFACE" | awk '{print $4}' || true)"
  if [[ -n "$IP_LIST2" ]]; then
    ok "Recovery: IPv4 present after forcing ${LL_CON}: ${IP_LIST2}"
  else
    warn "Still no IPv4 after ${LL_CON}. Forcing manual APIPA profile..."
    nmcli -w 10 con up "${UUID_APIPA}" >/dev/null 2>&1 || true
    sleep 5
    IP_LIST3="$(ip -o -4 addr show dev "$INTERFACE" | awk '{print $4}' || true)"
    if [[ -n "$IP_LIST3" ]]; then
      ok "Recovery: IPv4 present after forcing ${APIPA_CON}: ${IP_LIST3}"
    else
      die "Critical: Still no IPv4 on ${INTERFACE}. Check logs: journalctl -u NetworkManager -u network-fallback"
    fi
  fi
fi

ok "Setup + validation complete."
echo
echo "Helpful commands:"
echo "  nmcli con show --active"
echo "  nmcli -f ipv4.method,ipv4.link-local con show ${DHCP_CON}"
echo "  nmcli -g ipv4.link-local con show ${DHCP_CON}   # may print enum '4' for fallback"
echo "  ip -4 addr show dev ${INTERFACE}"
echo "  journalctl -u network-fallback -u NetworkManager --no-pager -n 200"
echo
echo "Direct-connect/no-DHCP test:"
echo "  1) Unplug from router/DHCP, connect Pi directly to PC."
echo "  2) Run: nmcli con up ${DHCP_CON}"
echo "  3) Watch: journalctl -u network-fallback -f"
