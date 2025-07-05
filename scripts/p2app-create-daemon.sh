#!/bin/bash
# p2app-create-daemon.sh 
# Written by: Jerry DeLong KD4YAL
# This script automates the daemon setup for p2app at the specified path, 
# ensuring it runs with the -p flag as root, with robust error handling and verification.

# chmod +xp2app-create-daemon.sh
# sudo ./p2app-create-daemon.sh

# sudo systemctl start p2app.service
# sudo systemctl stop p2app.service
# sudo systemctl status p2app.service

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Set repository and P2_app paths
REPO_PATH="/home/pi/github/Saturn"
P2_APP_DIR="$REPO_PATH/sw_projects/P2_app"
P2_APP_EXECUTABLE="$P2_APP_DIR/p2app"

# Verify repository path exists
if [ ! -d "$REPO_PATH" ]; then
  echo "Repository not found at $REPO_PATH"
  exit 1
fi

# Verify P2_app directory exists
if [ ! -d "$P2_APP_DIR" ]; then
  echo "P2_app directory not found at $P2_APP_DIR"
  exit 1
fi

# Navigate to P2_app directory and compile
cd "$P2_APP_DIR" || exit 1
make clean && make || { echo "Compilation failed"; exit 1; }

# Verify executable exists
if [ ! -f "$P2_APP_EXECUTABLE" ]; then
  echo "Executable $P2_APP_EXECUTABLE not found after compilation"
  exit 1
fi

# Ensure executable has correct permissions
chmod +x "$P2_APP_EXECUTABLE" || { echo "Failed to set executable permissions"; exit 1; }

# Create systemd service file
SERVICE_FILE="/etc/systemd/system/p2app.service"
cat > "$SERVICE_FILE" <<EOL
[Unit]
Description=P2_app Service for Saturn SDR
After=network.target

[Service]
WorkingDirectory=$P2_APP_DIR
ExecStart=$P2_APP_EXECUTABLE -s -p
User=root
Restart=always

[Install]
WantedBy=multi-user.target
EOL

# Verify service file creation
if [ ! -f "$SERVICE_FILE" ]; then
  echo "Failed to create service file at $SERVICE_FILE"
  exit 1
fi

# Reload systemd daemon
systemctl daemon-reload || { echo "Failed to reload systemd daemon"; exit 1; }

# Enable and start the service
systemctl enable p2app.service || { echo "Failed to enable p2app service"; exit 1; }
systemctl start p2app.service || { echo "Failed to start p2app service"; exit 1; }

# Check service status
systemctl status p2app.service

echo "P2_app daemon setup complete."
