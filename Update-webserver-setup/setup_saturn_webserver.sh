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

# Verify modular scripts exist
for script in install_deps.sh configure_apache.sh create_files.sh start_server.sh; do
    if [ ! -f "$SETUP_DIR/$script" ]; then
        log_and_echo "${RED}Error: $script not found in $SETUP_DIR${NC}"
        exit 1
    fi
    chmod 755 "$SETUP_DIR/$script"
    chown pi:pi "$SETUP_DIR/$script"
done

# Run modular scripts
log_and_echo "${CYAN}Starting setup at $(date)${NC}"

log_and_echo "${CYAN}Executing install_deps.sh...${NC}"
bash "$SETUP_DIR/install_deps.sh" >> "$LOG_FILE" 2>&1 || { log_and_echo "${RED}Error: install_deps.sh failed${NC}"; exit 1; }

log_and_echo "${CYAN}Executing configure_apache.sh...${NC}"
bash "$SETUP_DIR/configure_apache.sh" >> "$LOG_FILE" 2>&1 || { log_and_echo "${RED}Error: configure_apache.sh failed${NC}"; exit 1; }

log_and_echo "${CYAN}Executing create_files.sh...${NC}"
bash "$SETUP_DIR/create_files.sh" >> "$LOG_FILE" 2>&1 || { log_and_echo "${RED}Error: create_files.sh failed${NC}"; exit 1; }

log_and_echo "${CYAN}Executing start_server.sh...${NC}"
bash "$SETUP_DIR/start_server.sh" >> "$LOG_FILE" 2>&1 || { log_and_echo "${RED}Error: start_server.sh failed${NC}"; exit 1; }

private_ip=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | head -n1)
log_and_echo "${GREEN}Setup completed at $(date). Log: $LOG_FILE${NC}"
log_and_echo "${CYAN}Test LAN access with: curl -u admin:password123 http://$private_ip/saturn/${NC}"
