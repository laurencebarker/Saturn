#!/bin/bash
# install_deps_buster.sh - Installs dependencies for Saturn Update Manager on Raspbian Buster
# Version: 1.0
# Written by: Jerry DeLong KD4YAL
# Dependencies: bash
# Usage: Called by setup_saturn_webserver.sh on Buster systems

set -e

# Paths
VENV_PATH="/home/pi/venv"
LOG_DIR="/home/pi/saturn-logs"
LOG_FILE="$LOG_DIR/setup_saturn_webserver-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# Function to log and echo output
log_and_echo() {
    echo -e "$1" >&2
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE"
}

# Install system dependencies
log_and_echo "${CYAN}Updating package lists...${NC}"
apt update || { log_and_echo "${RED}Error: Updating package lists failed${NC}"; exit 1; }
log_and_echo "${GREEN}Updating package lists completed${NC}"

log_and_echo "${CYAN}Installing system dependencies...${NC}"
apt install -y apache2 apache2-utils python3 python3-venv python3-pip libapache2-mod-proxy-uwsgi lsof || { log_and_echo "${RED}Error: Installing system dependencies failed${NC}"; exit 1; }
a2enmod proxy proxy_http proxy_uwsgi rewrite ssl || { log_and_echo "${RED}Error: Enabling Apache modules failed${NC}"; exit 1; }
log_and_echo "${GREEN}System dependencies installed${NC}"

# Remove existing virtual environment as root
log_and_echo "${CYAN}Removing existing virtual environment at $VENV_PATH if exists...${NC}"
rm -rf "$VENV_PATH" || { log_and_echo "${RED}Error: Removing virtual environment failed${NC}"; exit 1; }

# Create virtual environment as pi user
log_and_echo "${CYAN}Creating virtual environment at $VENV_PATH...${NC}"
sudo -u pi python3 -m venv "$VENV_PATH" || { log_and_echo "${RED}Error: Creating virtual environment failed${NC}"; exit 1; }
chown -R pi:pi "$VENV_PATH"
log_and_echo "${GREEN}Virtual environment created${NC}"

# Install Python dependencies as pi user with Buster-compatible versions
log_and_echo "${CYAN}Installing Python dependencies...${NC}"
sudo -u pi bash -c "source $VENV_PATH/bin/activate && \
    pip install --upgrade pip setuptools wheel && \
    pip install flask==2.2.5 gunicorn ansi2html==1.9.2 psutil==5.9.8" || { log_and_echo "${RED}Error: Installing Python dependencies failed${NC}"; exit 1; }
log_and_echo "${GREEN}Python dependencies installed${NC}"
