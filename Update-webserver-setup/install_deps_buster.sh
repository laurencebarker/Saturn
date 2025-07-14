#!/bin/bash
# install_deps_buster.sh - Installs system and Python dependencies for Saturn Update Manager on Buster
# Version: 1.1
# Written by: Jerry DeLong KD4YAL
# Changes: Added gevent==21.12.0 to pip install for Buster-compatible async workers, updated version to 1.1
# Dependencies: bash, apt-get, python3, python3-venv, python3-pip
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

# Update package lists
log_and_echo "${CYAN}Updating package lists...${NC}"
apt-get update
log_and_echo "${GREEN}Updating package lists completed${NC}"

# Install system dependencies
log_and_echo "${CYAN}Installing system dependencies...${NC}"
apt-get install -y python3 python3-venv python3-pip apache2 apache2-utils libapache2-mod-proxy-uwsgi lsof
a2enmod proxy proxy_http proxy_uwsgi rewrite ssl
log_and_echo "${GREEN}System dependencies installed${NC}"

# Create virtual environment if not exists
log_and_echo "${CYAN}Removing existing virtual environment at $VENV_PATH if exists...${NC}"
rm -rf "$VENV_PATH"
log_and_echo "${CYAN}Creating virtual environment at $VENV_PATH...${NC}"
python3 -m venv "$VENV_PATH"
log_and_echo "${GREEN}Virtual environment created${NC}"

# Install Python dependencies
log_and_echo "${CYAN}Installing Python dependencies...${NC}"
source "$VENV_PATH/bin/activate"
pip install --upgrade pip setuptools wheel
pip install flask==2.2.5 ansi2html==1.9.2 psutil==5.9.8 gunicorn gevent==21.12.0
deactivate
log_and_echo "${GREEN}Python dependencies installed${NC}"
