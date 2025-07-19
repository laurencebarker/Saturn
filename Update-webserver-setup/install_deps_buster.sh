#!/bin/bash
# install_deps_buster.sh - Installs system and Python dependencies for Saturn Update Manager on Buster
# Version: 1.1
# Written by: Jerry DeLong KD4YAL
# Changes: Added gevent==21.12.0 to pip install for Buster-compatible async workers, updated version to 1.1
# Dependencies: bash, apt-get, python3, python3-venv, python3-pip
# Usage: Called by setup_saturn_webserver.sh on Buster systems

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
run_command "apt-get install -y python3 python3-venv python3-pip apache2 apache2-utils libapache2-mod-proxy-uwsgi lsof" "Installing system dependencies"
run_command "a2enmod proxy proxy_http proxy_uwsgi rewrite ssl" "Enabling Apache modules"

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

# Install Python dependencies as 'pi' user
log_and_echo "${CYAN}Installing Python dependencies...${NC}"
cmd="sudo -u pi $VENV_PATH/bin/pip install --upgrade pip setuptools wheel"
if output=$($cmd 2>&1); then
    log_and_echo "$output"
else
    log_and_echo "${RED}Error: Upgrading pip failed${NC}"
    log_and_echo "$output"
    exit 1
fi

cmd="sudo -u pi $VENV_PATH/bin/pip install flask==2.2.5 ansi2html==1.9.2 psutil==5.9.8 gunicorn gevent==21.12.0"
if output=$($cmd 2>&1); then
    log_and_echo "$output"
    log_and_echo "${GREEN}Installing Python dependencies completed${NC}"
else
    log_and_echo "${RED}Error: Installing Python dependencies failed${NC}"
    log_and_echo "$output"
    exit 1
fi

if ! sudo -u pi bash -c ". $VENV_PATH/bin/activate && python3 -c 'import flask, ansi2html, psutil, gunicorn, gevent' && which gunicorn" 2>/dev/null; then
    log_and_echo "${RED}Error: Virtual environment verification failed${NC}"
    exit 1
fi
log_and_echo "${GREEN}Virtual environment verified${NC}"
