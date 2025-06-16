#!/bin/bash
#
# Install serial port rules file in /etc/udev/rules.d
# This script must be run as root (use sudo)

# Determine the script's directory
SCRIPT_DIR=$(dirname "$0")

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root. Please run it with sudo."
    exit 1
fi

# Check if the rules file exists
RULES_FILE="$SCRIPT_DIR/61-g2-serial.rules"
if [ ! -f "$RULES_FILE" ]; then
    echo "ERROR: Rules file $RULES_FILE not found."
    exit 1
fi

echo "##############################################################"
echo ""
echo "Installing serial rules file:"
echo ""
echo "##############################################################"

# Copy the rules file
if cp "$RULES_FILE" /etc/udev/rules.d; then
    echo "✓ Rules file copied successfully."
else
    echo "ERROR: Failed to copy rules file."
    exit 1
fi

# Reload udev rules
if udevadm control --reload-rules && udevadm trigger; then
    echo "✓ Udev rules reloaded successfully."
else
    echo "ERROR: Failed to reload udev rules."
    exit 1
fi
