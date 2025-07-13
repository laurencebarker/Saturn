#!/bin/bash
# setup_saturn_webserver.sh - Main script to setup web server for saturn_update_manager.py on Raspberry Pi Bookworm
# Version: 2.65
# Written by: Jerry DeLong KD4YAL
# Changes: Modularized into smaller scripts (install_deps.sh, configure_apache.sh, create_files.sh, start_server.sh),
#          moved to ~/github/Saturn/Update-webserver-setup, removed --show-compile from update-pihpsdr.py flags,
#          merged its functionality into --verbose, updated update-pihpsdr.py to version 1.7,
#          added version display in index.html, added /saturn/get_versions endpoint,
#          enhanced output streaming, increased pre max-height to 500px,
#          updated /saturn/exit to force logoff and re-authentication,
#          fixed tput error in update scripts to display G2 Header banner, updated version to 2.65
# Dependencies: bash, scripts in ~/github/Saturn/Update-webserver-setup
# Usage: sudo bash ~/github/Saturn/Update-webserver-setup/setup_saturn_webserver.sh
# Notes: Orchestrates setup by calling modular scripts

set -e

# Check for sudo
[ "$EUID" -ne 0 ] && { echo -e "\033[0;31m[ERROR] This script must be run as root (use sudo)\033[0m"; exit 1; }

# Paths
SETUP_DIR="/home/pi/github/Saturn/Update-webserver-setup"
LOG_DIR="/home/pi/saturn-logs"
LOG_FILE="$LOG_DIR/setup_saturn_webserver-$(date +%Y%m%d-%H%M%S).log"
SCRIPTS_DIR="/home/pi/scripts"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Function to log and echo output
log_and_echo() {
    echo -e "$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE"
}

# Create log directory
log_and_echo "${CYAN}Creating log directory...${NC}"
mkdir -p "$LOG_DIR" || { log_and_echo "${RED}Error: Failed to create $LOG_DIR${NC}"; exit 1; }
chown pi:pi "$LOG_DIR"
chmod 775 "$LOG_DIR"

# Create setup directory
log_and_echo "${CYAN}Creating setup directory at $SETUP_DIR...${NC}"
mkdir -p "$SETUP_DIR" || { log_and_echo "${RED}Error: Failed to create $SETUP_DIR${NC}"; exit 1; }
chown pi:pi "$SETUP_DIR"
chmod 755 "$SETUP_DIR"

# Copy update scripts to ~/scripts
log_and_echo "${CYAN}Copying update-G2.py and update-pihpsdr.py to $SCRIPTS_DIR...${NC}"
mkdir -p "$SCRIPTS_DIR"
for script in update-G2.py update-pihpsdr.py; do
    if [ -f "$SETUP_DIR/$script" ]; then
        cp "$SETUP_DIR/$script" "$SCRIPTS_DIR/"
        chown pi:pi "$SCRIPTS_DIR/$script"
        chmod +x "$SCRIPTS_DIR/$script"
        log_and_echo "${GREEN}$script copied to $SCRIPTS_DIR${NC}"
    else
        log_and_echo "${YELLOW}$script not found in $SETUP_DIR, skipping${NC}"
    fi
done

# Detect OS version
source /etc/os-release

# Verify modular scripts exist
for script in configure_apache.sh create_files.sh; do
    if [ ! -f "$SETUP_DIR/$script" ]; then
        log_and_echo "${RED}Error: $script not found in $SETUP_DIR${NC}"
        exit 1
    fi
    chmod 755 "$SETUP_DIR/$script"
    chown pi:pi "$SETUP_DIR/$script"
done

# Check for Buster-specific deps and start scripts
if [ "$VERSION" = "10 (buster)" ]; then
    DEPS_SCRIPT="install_deps_buster.sh"
    START_SCRIPT="start_server_buster.sh"
else
    DEPS_SCRIPT="install_deps.sh"
    START_SCRIPT="start_server.sh"
fi

for script in "$DEPS_SCRIPT" "$START_SCRIPT"; do
    if [ ! -f "$SETUP_DIR/$script" ]; then
        log_and_echo "${RED}Error: $script not found in $SETUP_DIR${NC}"
        exit 1
    fi
    chmod 755 "$SETUP_DIR/$script"
    chown pi:pi "$SETUP_DIR/$script"
done

# Run modular scripts
log_and_echo "${CYAN}Starting setup at $(date)${NC}"

log_and_echo "${CYAN}Executing $DEPS_SCRIPT...${NC}"
bash "$SETUP_DIR/$DEPS_SCRIPT" >> "$LOG_FILE" 2>&1 || { log_and_echo "${RED}Error: $DEPS_SCRIPT failed${NC}"; exit 1; }

log_and_echo "${CYAN}Executing configure_apache.sh...${NC}"
bash "$SETUP_DIR/configure_apache.sh" >> "$LOG_FILE" 2>&1 || { log_and_echo "${RED}Error: configure_apache.sh failed${NC}"; exit 1; }

log_and_echo "${CYAN}Executing create_files.sh...${NC}"
bash "$SETUP_DIR/create_files.sh" >> "$LOG_FILE" 2>&1 || { log_and_echo "${RED}Error: create_files.sh failed${NC}"; exit 1; }

log_and_echo "${CYAN}Executing $START_SCRIPT...${NC}"
bash "$SETUP_DIR/$START_SCRIPT" >> "$LOG_FILE" 2>&1 || { log_and_echo "${RED}Error: $START_SCRIPT failed${NC}"; exit 1; }

private_ip=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | head -n1)
log_and_echo "${GREEN}Setup completed at $(date). Log: $LOG_FILE${NC}"
log_and_echo "${CYAN}Test LAN access with: curl -u admin:password123 http://$private_ip/saturn/${NC}"






18.1s
