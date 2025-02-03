#!/bin/bash
# update-G2.sh
# Pull repository and build p2app with error handling and status checks
# original script Laurence Barker G8NJJ
# substantially rewritten by KD4YAL - thank you

# Exit on any error
set -e

# Function to print section headers
print_header()
{
    echo "##############################################################"
    echo ""
    echo "$1"
    echo ""
    echo "##############################################################"
}

# Function to check command status
check_status()
{
    if [ $? -eq 0 ]; then
        echo "✓ $1 completed successfully"
    else
        echo "✗ Error: $1 failed"
        exit 1
    fi
}

# Define base directory
SATURN_DIR="$HOME/github/Saturn"

# Check if Saturn directory exists
if [ ! -d "$SATURN_DIR" ]; then
    echo "Error: Saturn directory not found at $SATURN_DIR"
    exit 1
fi

# Navigate to Saturn directory
cd "$SATURN_DIR" || exit 1


# check if necessary libraries have been installed
print_header "Installing libraries if required"
if [ -f "./scripts/install-libraries.sh" ]; then
    ./scripts/install-libraries.sh
    check_status "Library update"
else
    echo "Error: install-libraries.sh script not found"
    exit 1
fi


print_header "Updating G2: pulling new files from repository"

# Navigate to Saturn directory
cd "$SATURN_DIR" || exit 1

# Store current version for comparison
CURRENT_VERSION=$(git rev-parse HEAD)

# Configure and pull updates
git config pull.rebase false
git pull
check_status "Repository update"

# Check if update actually occurred
NEW_VERSION=$(git rev-parse HEAD)
if [ "$CURRENT_VERSION" == "$NEW_VERSION" ]; then
    echo "Note: Already up to date - no new updates found"
fi


print_header "Making p2app"
if [ -f "./scripts/update-p2app.sh" ]; then
    ./scripts/update-p2app.sh
    check_status "p2app build"
else
    echo "Error: update-p2app.sh script not found"
    exit 1
fi


print_header "Making desktop apps"
if [ -f "./scripts/update-desktop-apps.sh" ]; then
    ./scripts/update-desktop-apps.sh
    check_status "Desktop apps build"
else
    echo "Error: update-desktop-apps.sh script not found"
    exit 1
fi


print_header "Setting udev rules"
cd "$SATURN_DIR/rules" || exit 1
if [ -f "./install-rules.sh" ]; then
    sudo ./install-rules.sh
    check_status "udev rules installation"
else
    echo "Error: install-rules.sh script not found"
    exit 1
fi

print_header "Copying desktop icons"
cd "$SATURN_DIR" || exit 1
if [ -d "desktop" ] && [ -d "$HOME/Desktop" ]; then
    cp desktop/* "$HOME/Desktop"
    check_status "Desktop icons copy"
else
    echo "Error: desktop directory or Desktop folder not found"
    exit 1
fi



print_header "checking latest FPGA BIT filename"
if [ -f "./scripts/find-bin.sh" ]; then
    ./scripts/find-bin.sh
    check_status "Checking BIN file"
else
    echo "Error: find-bin.sh script not found"
    exit 1
fi

 

print_header "Update Complete"
echo "The Raspberry Pi programs have now all been updated."
echo ""
echo "FPGA Update Instructions:"
echo "1. If FPGA needs updating, launch flashwriter desktop app"
echo "2. Navigate: Open file → Home → github → Saturn → FPGA"
echo "3. Select the new .BIT file (eg saturnprimary2024V19.bin)"
echo "4. Ensure 'primary' is selected"
echo "5. Click 'Program'"
echo ""
echo "Note: Programming takes approximately 3 minutes"
echo "Important: Power cycle completely after programming"

# return to home directory
cd "$HOME"
