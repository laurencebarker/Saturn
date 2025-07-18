#!/bin/bash
# setup-eth-fallback.sh - enabling automatic IPv4 link-local (APIPA) fallback
# Version: 1.1
# Written by: Jerry DeLong, KD4YAL
# 20259715

## Setup-Eth-Fallback.sh Script Documentation
## Comprehensive overview of the setup-eth-fallback.sh Bash script, 
## designed as a one-and-done fix for enabling automatic IPv4 link-local (APIPA) fallback on
## Raspberry Pi OS Bookworm when no DHCP server is available (e.g., direct Ethernet connection
## to a PC running Thetis for radio setups). It addresses the change from dhcpcd to NetworkManager
## in Bookworm, which disables default link-local fallback.

## The script automates the creation of dual NetworkManager profiles (DHCP primary with fallback to link-local),
## installs dependencies if missing, sets up a monitoring service to ensure IP assignment, and validates the setup.
## It includes color-coded output for better readability during execution.

## 

# Color codes
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
RESET="\e[0m"

# Function to check and install dependencies
check_and_install() {
    local package="$1"
    if ! dpkg -s "$package" &> /dev/null; then
        echo -e "${YELLOW}Package $package is not installed. Installing...${RESET}"
        apt update
        apt install -y "$package"
        if [ $? -ne 0 ]; then
            echo -e "${RED}Error: Failed to install $package. Please install manually.${RESET}"
            exit 1
        fi
    else
        echo -e "${GREEN}Package $package is already installed.${RESET}"
    fi
}

# Check dependencies
check_and_install "network-manager"  # For nmcli
check_and_install "iproute2"        # For ip command
check_and_install "uuid-runtime"    # For uuidgen

# Configuration variables
INTERFACE="eth0"
DHCP_PROFILE="/etc/NetworkManager/system-connections/${INTERFACE}-dhcp.nmconnection"
LL_PROFILE="/etc/NetworkManager/system-connections/${INTERFACE}-ll.nmconnection"
MONITOR_SCRIPT="/usr/local/bin/network-monitor.sh"
SERVICE_FILE="/etc/systemd/system/network-fallback.service"

# Create dual profiles if they don't exist
if [ -f "$DHCP_PROFILE" ] && [ -f "$LL_PROFILE" ]; then
    echo -e "${GREEN}Dual profiles already exist. Skipping creation.${RESET}"
else
    echo -e "${YELLOW}Creating dual NetworkManager profiles...${RESET}"

    # Generate UUIDs
    UUID_DHCP=$(uuidgen)
    UUID_LL=$(uuidgen)

    # Create DHCP profile (high priority, short DHCP timeout)
    cat <<EOF > "$DHCP_PROFILE"
[connection]
id=${INTERFACE}-dhcp
uuid=$UUID_DHCP
type=ethernet
interface-name=$INTERFACE
autoconnect-priority=100
autoconnect-retries=2

[ethernet]

[ipv4]
dhcp-timeout=3
method=auto

[ipv6]
addr-gen-mode=default
method=auto

[proxy]
EOF

    # Create link-local fallback profile (lower priority)
    cat <<EOF > "$LL_PROFILE"
[connection]
id=${INTERFACE}-ll
uuid=$UUID_LL
type=ethernet
interface-name=$INTERFACE
autoconnect-priority=50

[ethernet]

[ipv4]
method=link-local

[ipv6]
addr-gen-mode=default
method=auto

[proxy]
EOF

    # Set permissions
    chmod 600 "$DHCP_PROFILE" "$LL_PROFILE"

    # Reload NetworkManager
    nmcli con reload
    echo -e "${GREEN}Profiles created and reloaded.${RESET}"
fi

# Create monitor script if it doesn't exist
if [ ! -f "$MONITOR_SCRIPT" ]; then
    echo -e "${YELLOW}Creating monitor script at $MONITOR_SCRIPT...${RESET}"
    cat <<EOF > "$MONITOR_SCRIPT"
#!/bin/bash

INTERFACE="$INTERFACE"
CHECK_INTERVAL=30  # Seconds between checks
NO_IP_TIMEOUT=60  # Total seconds without IP before forcing fallback

while true; do
    sleep \$CHECK_INTERVAL
    IP_ADDR=\$(ip -4 addr show \$INTERFACE | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}')
    if [ -z "\$IP_ADDR" ]; then
        echo "\$(date): No IPv4 on \$INTERFACE. Waiting \$NO_IP_TIMEOUT seconds before forcing fallback..."
        sleep \$NO_IP_TIMEOUT
        IP_ADDR=\$(ip -4 addr show \$INTERFACE | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}')
        if [ -z "\$IP_ADDR" ]; then
            echo "\$(date): Timeout exceeded. Forcing link-local profile..."
            nmcli con up "${INTERFACE}-ll"
        fi
    else
        echo "\$(date): IPv4 present (\$IP_ADDR). Monitoring continues."
    fi
done
EOF
    chmod +x "$MONITOR_SCRIPT"
    echo -e "${GREEN}Monitor script created.${RESET}"
else
    echo -e "${GREEN}Monitor script already exists. Skipping creation.${RESET}"
fi

# Create systemd service file if it doesn't exist
if [ ! -f "$SERVICE_FILE" ]; then
    echo -e "${YELLOW}Creating systemd service at $SERVICE_FILE...${RESET}"
    cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Network Fallback Monitor Service
After=network.target NetworkManager.service

[Service]
Type=simple
ExecStart=$MONITOR_SCRIPT
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    echo -e "${GREEN}Systemd service created.${RESET}"
else
    echo -e "${GREEN}Systemd service already exists. Skipping creation.${RESET}"
fi

# Reload systemd, enable and start the service
systemctl daemon-reload
systemctl enable network-fallback.service
systemctl start network-fallback.service
echo -e "${GREEN}Systemd service enabled and started.${RESET}"

# Validation: Activate DHCP profile and check status
echo -e "${YELLOW}Validating setup...${RESET}"
nmcli con down "$INTERFACE"-dhcp &> /dev/null  # Ensure it's down first
nmcli con down "$INTERFACE"-ll &> /dev/null
nmcli con up "$INTERFACE"-dhcp

sleep 10  # Wait for connection attempt

# Check if connection is active
ACTIVE_CON=$(nmcli -t -f NAME con show --active | grep "$INTERFACE"-dhcp)
if [ -n "$ACTIVE_CON" ]; then
    echo -e "${GREEN}DHCP profile activated successfully.${RESET}"
else
    echo -e "${YELLOW}Warning: DHCP profile failed to activate. Check 'nmcli con show' or logs.${RESET}"
fi

# Check for IPv4 address on interface (DHCP or fallback)
IP_ADDR=$(ip -4 addr show $INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
if [ -n "$IP_ADDR" ]; then
    echo -e "${GREEN}Validation passed: IPv4 address assigned ($IP_ADDR).${RESET}"
    if [[ $IP_ADDR =~ ^169\.254\. ]]; then
        echo -e "${GREEN}Note: This is a link-local address (fallback active).${RESET}"
    else
        echo -e "${GREEN}Note: This appears to be a DHCP-assigned address.${RESET}"
    fi
else
    echo -e "${YELLOW}Validation failed: No IPv4 address on $INTERFACE. Forcing link-local...${RESET}"
    nmcli con up "$INTERFACE"-ll
    sleep 5
    IP_ADDR=$(ip -4 addr show $INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    if [ -n "$IP_ADDR" ]; then
        echo -e "${GREEN}Link-local forced: IPv4 address now $IP_ADDR.${RESET}"
    else
        echo -e "${RED}Critical: Still no IP. Check hardware, cables, or NetworkManager logs (journalctl -u NetworkManager).${RESET}"
        exit 1
    fi
fi

echo -e "${GREEN}Basic validation complete. For full fallback test:${RESET}"
echo "1. Disconnect from any router/DHCP source (e.g., direct connect to PC)."
echo "2. Reboot or run 'nmcli con up ${INTERFACE}-dhcp'."
echo "3. After ~10s, check 'ip addr show $INTERFACE' for a 169.254.x.x address."
echo -e "${GREEN}Setup automation complete. Monitor service is running (check with 'systemctl status network-fallback').${RESET}"
