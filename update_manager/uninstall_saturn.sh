#!/bin/bash
# uninstall_saturn.sh - Uninstall Saturn Update Manager
# Version: 1.4
# Date: July 29, 2025
# Usage: sudo bash uninstall_saturn.sh

logger() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

logger "Stopping services..."
sudo systemctl stop apache2 2>/dev/null || logger "Failed to stop apache2"
sudo systemctl stop saturn-update-manager 2>/dev/null || logger "Failed to stop saturn-update-manager"

logger "Disabling services..."
sudo systemctl disable apache2 2>/dev/null || logger "Failed to disable apache2"
sudo systemctl disable saturn-update-manager 2>/dev/null || logger "Failed to disable saturn-update-manager"

logger "Removing systemd service..."
sudo rm -f /etc/systemd/system/saturn-update-manager.service
sudo systemctl daemon-reload
sudo systemctl reset-failed

logger "Removing Apache configuration..."
sudo rm -f /etc/apache2/sites-available/saturn.conf
sudo rm -f /etc/apache2/sites-enabled/saturn.conf
sudo rm -f /etc/apache2/conf-available/servername.conf
sudo rm -f /etc/apache2/conf-enabled/servername.conf
sudo rm -f /etc/apache2/.htpasswd
sudo a2disconf status 2>/dev/null || logger "Failed to disable status.conf"
sudo a2dismod -f proxy proxy_http auth_basic authn_file authz_core authz_host authz_user rewrite 2>/dev/null || logger "Failed to disable Apache modules"
sudo systemctl restart apache2 2>/dev/null || logger "Failed to restart apache2"

logger "Removing virtual environment..."
sudo rm -rf /home/pi/venv || logger "Failed to remove /home/pi/venv"

logger "Removing configs and templates..."
sudo rm -rf /home/pi/.saturn || logger "Failed to remove /home/pi/.saturn"
if [ -d "/home/pi/.saturn" ]; then
    logger "ERROR: /home/pi/.saturn still exists, attempting manual cleanup..."
    sudo chmod -R 777 /home/pi/.saturn
    sudo rm -rf /home/pi/.saturn || logger "ERROR: Manual cleanup of /home/pi/.saturn failed"
fi

logger "Removing logs..."
sudo rm -rf /home/pi/saturn-logs || logger "Failed to remove /home/pi/saturn-logs"

logger "Removing desktop shortcut..."
sudo rm -f /home/pi/Desktop/SaturnUpdateManager.desktop || logger "Failed to remove desktop shortcut"

logger "Removing temporary files..."
sudo rm -f /tmp/saturn-fallback.log || logger "Failed to remove /tmp/saturn-fallback.log"

logger "Removing hosts entry..."
sudo sed -i '/raspberrypi.local/d' /etc/hosts || logger "Failed to remove hosts entry"

logger "Killing any lingering Gunicorn processes..."
sudo pkill -f gunicorn 2>/dev/null || logger "No Gunicorn processes found"

logger "Uninstall complete. Run the installer for a fresh setup."
