#!/bin/bash

# p2app-create-daemon.sh
# Script to set up the P2_app daemon for ANAN G2
# Runs p2app with -s and -p flags as root, ensuring startup at boot
# Version: 2.3, Date: 2025-07-05
# Written by: Jerry DeLong KD4YAL

# Usage:
#   chmod +x p2app-create-daemon.sh
#   sudo ./p2app-create-daemon.sh
#   sudo systemctl start p2app.service
#   sudo systemctl stop p2app.service
#   sudo systemctl status p2app.service
#   sudo systemctl enable p2app.service

# Exit on any error
set -e

# Configuration variables
REPO_PATH="/home/pi/github/Saturn"
P2_APP_DIR="$REPO_PATH/sw_projects/P2_app"
P2_APP_EXECUTABLE="$P2_APP_DIR/p2app"
SERVICE_FILE="/etc/systemd/system/p2app.service"
LOG_FILE="/var/log/p2app-setup.log"
AUTOSTART_FILE="/home/pi/.config/autostart/g2-autostart-p2app.desktop"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Logging function
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" | tee -a "$LOG_FILE"
}

# Error handling function
error_exit() {
    local message="$1"
    log "ERROR: $message"
    echo -e "${RED}Error: $message${NC}"
    exit 1
}

# Check if running as root
check_root() {
    log "Checking for root privileges"
    if [ "$EUID" -ne 0 ]; then
        error_exit "This script must be run as root"
    fi
}

# Create and set permissions for log directory
setup_logging() {
    log "Setting up logging"
    local log_dir
    log_dir="$(dirname "$LOG_FILE")"
    mkdir -p "$log_dir" || error_exit "Failed to create log directory $log_dir"
    chmod 750 "$log_dir" || error_exit "Failed to set permissions for log directory $log_dir"
    log "Log directory $log_dir configured"
}

# Install dependencies
install_dependencies() {
    log "Checking and installing dependencies"
    if command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt"
        PKG_UPDATE="apt-get update"
        PKG_INSTALL="apt-get install -y"
    else
        error_exit "No supported package manager found (apt required)"
    fi
    $PKG_UPDATE || log "WARNING: Failed to update package lists, continuing..."

    # Install make
    if ! command -v make &>/dev/null; then
        log "Installing make"
        $PKG_INSTALL make || error_exit "Failed to install make"
    else
        log "make is already installed"
    fi

    # Install gcc
    if ! command -v gcc &>/dev/null; then
        log "Installing gcc"
        $PKG_INSTALL gcc || error_exit "Failed to install gcc"
    else
        log "gcc is already installed"
    fi

    # Install libgpiod
    if ! ldconfig -p | grep -q libgpiod; then
        log "Installing libgpiod-dev"
        $PKG_INSTALL libgpiod-dev || error_exit "Failed to install libgpiod-dev"
    else
        log "libgpiod is already installed"
    fi

    # Install libi2c
    if ! ldconfig -p | grep -q libi2c; then
        log "Installing libi2c-dev"
        $PKG_INSTALL libi2c-dev || error_exit "Failed to install libi2c-dev"
    else
        log "libi2c is already installed"
    fi
}

# Verify paths
verify_paths() {
    log "Verifying paths"
    if [ ! -d "$REPO_PATH" ]; then
        error_exit "Repository not found at $REPO_PATH"
    fi
    if [ ! -d "$P2_APP_DIR" ]; then
        error_exit "P2_app directory not found at $P2_APP_DIR"
    fi
    log "Paths verified: $REPO_PATH, $P2_APP_DIR"
}

# Compile P2_app
compile_p2app() {
    log "Navigating to $P2_APP_DIR for compilation"
    cd "$P2_APP_DIR" || error_exit "Failed to change to directory $P2_APP_DIR"
    log "Running make clean && make"
    make clean && make || error_exit "Compilation failed"
    if [ ! -f "$P2_APP_EXECUTABLE" ]; then
        for alt_name in P2_app p2_app; do
            if [ -f "$P2_APP_DIR/$alt_name" ]; then
                P2_APP_EXECUTABLE="$P2_APP_DIR/$alt_name"
                log "Found alternative executable: $P2_APP_EXECUTABLE"
                break
            fi
        done
        if [ ! -f "$P2_APP_EXECUTABLE" ]; then
            error_exit "Executable not found at $P2_APP_EXECUTABLE or alternatives after compilation"
        fi
    fi
    log "Compilation successful: $P2_APP_EXECUTABLE"
    log "Executable details: $(ls -l "$P2_APP_EXECUTABLE")"
}

# Set executable permissions
set_permissions() {
    log "Setting permissions for $P2_APP_EXECUTABLE"
    chmod 755 "$P2_APP_EXECUTABLE" || error_exit "Failed to set permissions for $P2_APP_EXECUTABLE"
    chown root:root "$P2_APP_EXECUTABLE" || error_exit "Failed to set ownership for $P2_APP_EXECUTABLE"
    log "Permissions set for $P2_APP_EXECUTABLE"
}

# Remove autostart desktop file
remove_autostart_file() {
    log "Checking for autostart file $AUTOSTART_FILE"
    if [ -f "$AUTOSTART_FILE" ]; then
        log "Removing autostart file $AUTOSTART_FILE"
        rm -f "$AUTOSTART_FILE" || error_exit "Failed to remove autostart file $AUTOSTART_FILE"
        log "Autostart file removed"
    else
        log "No autostart file found at $AUTOSTART_FILE"
    fi
}

# Create systemd service file
create_service_file() {
    log "Creating systemd service file at $SERVICE_FILE"
    if [ ! -x "$P2_APP_EXECUTABLE" ]; then
        error_exit "Executable $P2_APP_EXECUTABLE is not executable or does not exist"
    fi
    cat > "$SERVICE_FILE" <<EOL
[Unit]
Description=P2_app Service for ANAN G2
After=network.target
Documentation=https://github.com/laurencebarker/Saturn

[Service]
WorkingDirectory=$P2_APP_DIR
ExecStart=$P2_APP_EXECUTABLE -s -p
User=root
Group=root
Restart=always
RestartSec=5
TimeoutStopSec=30
Environment=LD_LIBRARY_PATH=/usr/local/lib:/usr/lib
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
StandardOutput=syslog
StandardError=syslog
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOL
    log "Generated service file with ExecStart=$P2_APP_EXECUTABLE -s -p"
    if [ ! -f "$SERVICE_FILE" ]; then
        error_exit "Failed to create service file at $SERVICE_FILE"
    fi
    chmod 644 "$SERVICE_FILE" || error_exit "Failed to set permissions for $SERVICE_FILE"
    if ! grep -q "^User=root$" "$SERVICE_FILE"; then
        error_exit "Failed to configure service to run as root"
    fi
    log "Systemd service file created"
}

# Verify service status
verify_service_status() {
    log "Verifying p2app service status"
    sleep 1  # Allow service to stabilize
    if systemctl is-active p2app.service | grep -q "^active"; then
        log "p2app service is active"
    else
        log "ERROR: p2app service failed to start"
        systemctl status p2app.service || log "WARNING: Failed to check p2app service status"
        error_exit "p2app service is not active. Check logs with 'journalctl -u p2app.service'"
    fi
}

# Main execution
check_root
setup_logging
install_dependencies
verify_paths
compile_p2app
set_permissions
remove_autostart_file
create_service_file
systemctl daemon-reload || error_exit "Failed to reload systemd daemon"
systemctl enable p2app.service || error_exit "Failed to enable p2app service"
systemctl start p2app.service || error_exit "Failed to start p2app service"
verify_service_status
echo -e "${GREEN}P2_app daemon setup complete.${NC}"
log "P2_app daemon setup complete"
