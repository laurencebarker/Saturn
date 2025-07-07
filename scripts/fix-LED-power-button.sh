#!/bin/bash
# fix-LED-power-button.sh
# Written by: Jerry DeLong KD4YAL
# Script to automate creation of gpio15-setup.service for controlling power LED
# Sets GPIO15 as output driven high at startup using pinctrl
# Runs in /etc/systemd/system, logs to journalctl

# The shutdown script is better as a systemd service for reliability and autonomy. 
# The shutdown_monitor.sh and shutdown-monitor.service above address all limitations. 
# The fix-LED-power-button.sh ensures gpio15-setup.service is correctly set up. The LED issue 
# requires testing GPIO15 and triggers. Please share:

# journalctl -t fix-LED-power-button output.
# sudo systemctl status shutdown-monitor.service output.
# GPIO15 test results (pinctrl set 15 op dh/dl).
# LED trigger test results (led1/default-on).



SERVICE_FILE="/etc/systemd/system/gpio15-setup.service"
CONFIG_FILE="/boot/config.txt"

# Function to log messages to journalctl
log_message() {
    echo "$1" | systemd-cat -t fix-LED-power-button
}

# Check if running with root privileges
if [ "$(id -u)" -ne 0 ]; then
    log_message "Error: This script requires root privileges. Run with sudo."
    exit 1
fi

# Check if pinctrl is installed
if ! command -v pinctrl >/dev/null 2>&1; then
    log_message "pinctrl not found. Attempting to install..."
    if ! apt update && apt install -y cmake device-tree-compiler libfdt-dev; then
        log_message "Error: Failed to install prerequisites for pinctrl."
        exit 1
    fi
    if ! git clone https://github.com/raspberrypi/utils /tmp/utils; then
        log_message "Error: Failed to clone raspberrypi/utils repository."
        exit 1
    fi
    cd /tmp/utils/pinctrl
    if ! cmake . || ! make || ! make install; then
        log_message "Error: Failed to build and install pinctrl."
        exit 1
    fi
    rm -rf /tmp/utils
    log_message "pinctrl installed successfully at /usr/bin/pinctrl"
fi

# Verify pinctrl path
PINCTRL_PATH=$(which pinctrl)
if [ "$PINCTRL_PATH" != "/usr/bin/pinctrl" ]; then
    log_message "Error: pinctrl not found at /usr/bin/pinctrl. Found at $PINCTRL_PATH"
    exit 1
fi

# Check for conflicting gpio=15 setting in /boot/config.txt
if grep -q "^gpio=15=op,dh" "$CONFIG_FILE"; then
    log_message "Found conflicting gpio=15=op,dh in $CONFIG_FILE. Commenting out..."
    if ! sed -i 's/^gpio=15=op,dh/#gpio=15=op,dh/' "$CONFIG_FILE"; then
        log_message "Error: Failed to comment out gpio=15=op,dh in $CONFIG_FILE."
        exit 1
    fi
    log_message "gpio=15=op,dh commented out. Reboot required after completion."
fi

# Create or update gpio15-setup.service
log_message "Creating/updating $SERVICE_FILE"
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Set GPIO15 at startup
After=sysinit.target

[Service]
ExecStart=/usr/bin/pinctrl set 15 op dh
Type=oneshot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

if [ $? -ne 0 ]; then
    log_message "Error: Failed to create $SERVICE_FILE"
    exit 1
fi

# Set permissions
chmod 644 "$SERVICE_FILE"
log_message "$SERVICE_FILE created successfully"

# Reload systemd, enable, and start
log_message "Reloading systemd and enabling gpio15-setup.service"
systemctl daemon-reload
if ! systemctl enable gpio15-setup.service; then
    log_message "Error: Failed to enable gpio15-setup.service"
    exit 1
fi
if ! systemctl start gpio15-setup.service; then
    log_message "Error: Failed to start gpio15-setup.service"
    exit 1
fi

# Verify GPIO15 state
log_message "Verifying GPIO15 state"
GPIO_STATE=$(pinctrl get 15)
if [[ "$GPIO_STATE" == *"op dh"* ]]; then
    log_message "GPIO15 set to output high: $GPIO_STATE"
else
    log_message "Warning: GPIO15 not set to output high. Current state: $GPIO_STATE"
fi

# Instructions for LED troubleshooting
log_message "Setup complete. Test the power LED:"
log_message "  sudo pinctrl set 15 op dh  # High (possible red)"
log_message "  sudo pinctrl set 15 op dl  # Low (possible white)"
log_message "Check /sys/class/leds/led1 or /sys/class/leds/default-on:"
log_message "  echo actpwr | sudo tee /sys/class/leds/led1/trigger"
log_message "If /boot/config.txt was modified, reboot with 'sudo reboot'."
exit 0
