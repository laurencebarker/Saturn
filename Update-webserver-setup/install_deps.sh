#!/bin/bash
# install_deps.sh - Installs system and Python dependencies for Saturn Update Manager
# Version: 1.0
# Written by: Jerry DeLong KD4YAL
# Dependencies: apt-get, python3, python3-pip
# Usage: Called by setup_saturn_webserver.sh

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

# Install system dependencies
run_command "apt-get update" "Updating package lists"
run_command "apt-get install -y python3 python3-pip lsof apache2 apache2-utils python3-gunicorn" "Installing system dependencies"

# Setup virtual environment
log_and_echo "${CYAN}Creating virtual environment at $VENV_PATH...${NC}"
if [ ! -d "$VENV_PATH" ]; then
    run_command "python3 -m venv $VENV_PATH" "Creating virtual environment"
    chmod -R u+rwX "$VENV_PATH"
else
    log_and_echo "${GREEN}Virtual environment already exists${NC}"
fi
run_command "sudo -u pi $VENV_PATH/bin/pip install flask ansi2html==1.9.2 psutil==7.0.0 pyfiglet gunicorn" "Installing Python dependencies"
if ! sudo -u pi bash -c ". $VENV_PATH/bin/activate && python3 -c 'import flask, ansi2html, psutil, pyfiglet, gunicorn' && which gunicorn" 2>/dev/null; then
    log_and_echo "${RED}Error: Virtual environment verification failed${NC}"
    exit 1
fi
log_and_echo "${GREEN}Virtual environment verified${NC}"
