#!/bin/bash
# setup_saturn_webserver.sh - Main setup script for Saturn Update Manager web server
# Version: 2.71
# Written by: Jerry DeLong KD4YAL
# Changes: Removed optional venv reset (now handled in install_deps.sh), updated to call fixed install_deps.sh v1.3, version to 2.71
# Dependencies: bash
# Usage: sudo bash setup_saturn_webserver.sh

set -e

# Paths
SCRIPTS_DIR="/home/pi/scripts"
LOG_DIR="/home/pi/saturn-logs"
LOG_FILE="$LOG_DIR/setup_saturn_webserver-$(date +%Y%m%d-%H%M%S).log"
UPDATE_DIR="/home/pi/github/Saturn/Update-webserver-setup"
SYSTEMD_SERVICE="/etc/systemd/system/saturn-update-manager.service"

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

# Create log directory if not exists
mkdir -p "$LOG_DIR"
chown pi:pi "$LOG_DIR"
chmod 775 "$LOG_DIR"

# Detect OS version
OS_VERSION=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d '"' -f2)
log_and_echo "${CYAN}Detected OS: $OS_VERSION${NC}"

if echo "$OS_VERSION" | grep -iq "buster"; then
    INSTALL_DEPS_SCRIPT="$UPDATE_DIR/install_deps_buster.sh"
    START_SERVER_SCRIPT="$UPDATE_DIR/start_server_buster.sh"
else
    INSTALL_DEPS_SCRIPT="$UPDATE_DIR/install_deps.sh"
    START_SERVER_SCRIPT="$UPDATE_DIR/start_server.sh"
fi

# Run install dependencies
log_and_echo "${CYAN}Running install dependencies...${NC}"
bash "$INSTALL_DEPS_SCRIPT"

# Configure Apache
log_and_echo "${CYAN}Configuring Apache...${NC}"
bash "$UPDATE_DIR/configure_apache.sh"

# Create files
log_and_echo "${CYAN}Creating files...${NC}"
bash "$UPDATE_DIR/create_files.sh"

# Start server
log_and_echo "${CYAN}Starting server...${NC}"
bash "$START_SERVER_SCRIPT"

# Setup systemd service for auto-restart
log_and_echo "${CYAN}Setting up systemd service for auto-restart...${NC}"
cat > "$SYSTEMD_SERVICE" << EOF
[Unit]
Description=Saturn Update Manager Gunicorn Server
After=network.target

[Service]
User=pi
Group=pi
WorkingDirectory=$SCRIPTS_DIR
Environment="PYTHONPATH=$SCRIPTS_DIR"
ExecStart=/home/pi/venv/bin/gunicorn --chdir $SCRIPTS_DIR -w 5 --worker-class gevent -b 0.0.0.0:5000 -t 600 saturn_update_manager:app
Restart=always
RestartSec=5s
StandardOutput=append:/home/pi/saturn-logs/saturn-update-manager.log
StandardError=append:/home/pi/saturn-logs/saturn-update-manager-error.log

[Install]
WantedBy=multi-user.target
EOF
chmod 644 "$SYSTEMD_SERVICE"
systemctl daemon-reload
systemctl enable saturn-update-manager
systemctl start saturn-update-manager
if systemctl status saturn-update-manager >/dev/null 2>&1; then
    log_and_echo "${GREEN}Systemd service enabled and started successfully${NC}"
else
    log_and_echo "${RED}Error: Systemd service failed to start${NC}"
    exit 1
fi

log_and_echo "${GREEN}Setup completed successfully. Access via curl -u admin:password123 http://$(hostname -I | awk '{print $1}')/saturn/${NC}"
