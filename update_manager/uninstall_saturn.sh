#!/bin/bash
# uninstall_saturn.sh - Uninstall Saturn Update Manager
# Version: 1.0
# Date: July 29, 2025
# Usage: sudo bash uninstall_saturn.sh

logger() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

logger "Stopping services..."
sudo systemctl stop apache2
sudo systemctl stop saturn-update-manager

logger "Disabling services..."
sudo systemctl disable apache2
sudo systemctl disable saturn-update-manager

logger "Removing systemd service..."
sudo rm -f /etc/systemd/system/saturn-update-manager.service
sudo systemctl daemon-reload

logger "Removing Apache configuration..."
sudo rm -f /etc/apache2/sites-available/saturn.conf
sudo rm -f /etc/apache2/sites-enabled/saturn.conf
sudo rm -f /etc/apache2/conf-available/servername.conf
sudo rm -f /etc/apache2/conf-enabled/servername.conf
sudo rm -f /etc/apache2/.htpasswd
sudo a2dismod proxy proxy_http auth_basic authn_file authz_core rewrite
sudo systemctl restart apache2

logger "Removing virtual environment..."
rm -rf ~/venv

logger "Removing configs and templates..."
rm -rf ~/.saturn

logger "Removing logs..."
rm -rf ~/saturn-logs

logger "Removing desktop shortcut..."
rm -f ~/Desktop/SaturnUpdateManager.desktop

logger "Removing hosts entry..."
sudo sed -i '/raspberrypi.local/d' /etc/hosts

logger "Uninstall complete. Run the installer for a fresh setup."