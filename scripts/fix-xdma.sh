#!/bin/bash
# fix-xdma.sh
# Version: 1.3
# Written by: Jerry DeLong KD4YAL
# Dependencies:  kernel headers
# Usage:  sudo bash fix-xdma.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Check if kernel headers are installed
KERNEL_BUILD_DIR="/lib/modules/$(uname -r)/build"
if [ ! -d "$KERNEL_BUILD_DIR" ]; then
    echo -e "${RED}Kernel headers not found. Attempting to install...${NC}"
    sudo apt update || {
        echo -e "${RED}Error: Failed to run apt update.${NC}"
        exit 1
    }
    sudo apt install raspberrypi-kernel-headers -y || {
        echo -e "${RED}Error: Failed to install raspberrypi-kernel-headers.${NC}"
        echo "If this fails, you may need to use rpi-update and rpi-source for matching headers."
        exit 1
    }
    # Recheck after installation
    if [ ! -d "$KERNEL_BUILD_DIR" ]; then
        echo -e "${RED}Error: Kernel headers still not found after installation attempt."
        echo "Please install manually or check your kernel version.${NC}"
        exit 1
    fi
    echo -e "${GREEN}Kernel headers installed successfully.${NC}"
fi

# Determine the driver directory based on whether running as root or not
if [ "$(id -u)" != "0" ]; then
    DRIVER_DIR="$HOME/github/Saturn/linuxdriver/xdma"
else
    if [ -n "$SUDO_USER" ]; then
        DRIVER_DIR="/home/$SUDO_USER/github/Saturn/linuxdriver/xdma"
    else
        DRIVER_DIR="/home/pi/github/Saturn/linuxdriver/xdma"  # Fallback for Raspberry Pi default user
    fi
fi

# Unload the previous driver from memory if it's loaded
sudo rmmod -s xdma 2>/dev/null || true

# Change directory to the driver directory
cd "$DRIVER_DIR" || {
    echo -e "${RED}Error: Driver directory not found at $DRIVER_DIR.${NC}"
    exit 1
}

# Optional: Clean before install (added based on your manual steps)
sudo make clean || {
    echo -e "${RED}Warning: make clean failed, proceeding anyway.${NC}"
}

# Compile and install the kernel module driver
sudo make install || {
    echo -e "${RED}Error: Failed to compile and install the driver.${NC}"
    exit 1
}

# Load the kernel module driver
sudo modprobe xdma || {
    echo -e "${RED}Error: Failed to load the driver.${NC}"
    exit 1
}

# Validate that the driver is installed and loaded
if lsmod | grep -q "^xdma "; then
    echo -e "${GREEN}Success: The xdma driver is installed and loaded.${NC}"
else
    echo -e "${RED}Error: Driver validation failed - xdma module not found in lsmod.${NC}"
    exit 1
fi
