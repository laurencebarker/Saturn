#!/bin/bash
# install_deps.sh - Installs system and Python dependencies for Saturn Update Manager
# Version: 1.5
# Written by: Jerry DeLong KD4YAL
# Changes: Added verbose (-v) and increased timeout to pip to prevent hangs, wrapped pip in timeout command, explicitly use piwheels index, updated version to 1.4
# Dependencies: apt-get, python3, python3-pip, timeout (coreutils)
# Usage: Called by setup_saturn_webserver.sh

set -e

# Check if running as root
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}Error: This script must be run with sudo or as root to perform APT operations.${NC}" >&2
    exit 1
fi

# Paths
VENV_PATH="/home/pi/venv"
LOG_DIR="/home/pi/saturn-logs"
LOG_FILE="$LOG_DIR/setup_saturn_webserver-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Function to log and echo output
log_and_echo() {
    echo -e "$1" >&2
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE"
}

# Function to run command, log, and echo output
run_command() {
    local cmd="$1" desc="$2"
    log_and_echo "${CYAN}$desc...${NC}"
    if output=$($cmd 2>&1); then
        log_and_echo "$output"
        log_and_echo "${GREEN}$desc completed${NC}"
    else
        log_and_echo "${RED}Error: $desc failed${NC}"
        log_and_echo "$output"
        exit 1
    fi
}

# Install system dependencies (requires sudo)
export DEBIAN_FRONTEND=noninteractive  # Make apt non-interactive to avoid prompts
run_command "apt-get update" "Updating package lists"
run_command "apt-get install -y python3 python3-pip lsof apache2 apache2-utils python3-gunicorn build-essential python3-dev" "Installing system dependencies"

# Reset and recreate virtual environment as 'pi' user to fix permissions
log_and_echo "${CYAN}Resetting and creating virtual environment at $VENV_PATH...${NC}"
if [ -d "$VENV_PATH" ]; then
    rm -rf "$VENV_PATH"
    log_and_echo "${YELLOW}Existing venv deleted for clean recreation${NC}"
fi
sudo -u pi python3 -m venv $VENV_PATH
log_and_echo "${GREEN}Virtual environment created${NC}"
sudo chown -R pi:pi $VENV_PATH
sudo chmod -R 755 $VENV_PATH

# Install Python packages as 'pi' user with verbose, timeout, and piwheels as extra index
log_and_echo "${CYAN}Installing Python dependencies...${NC}"
cmd="sudo -u pi timeout 600 $VENV_PATH/bin/pip install -v --timeout 120 --extra-index-url https://www.piwheels.org/simple flask ansi2html==1.9.2 psutil==7.0.0 pyfiglet gunicorn gevent"
if output=$($cmd 2>&1); then
    log_and_echo "$output"
    log_and_echo "${GREEN}Installing Python dependencies completed${NC}"
else
    log_and_echo "${RED}Error: Installing Python dependencies failed or timed out${NC}"
    log_and_echo "$output"
    exit 1
fi

if ! sudo -u pi bash -c ". $VENV_PATH/bin/activate && python3 -c 'import flask, ansi2html, psutil, pyfiglet, gunicorn, gevent' && which gunicorn" 2>/dev/null; then
    log_and_echo "${RED}Error: Virtual environment verification failed${NC}"
    exit 1
fi
log_and_echo "${GREEN}Virtual environment verified${NC}"
