#!/bin/bash

# Script to install 

echo "Installing libraries..."
sudo apt-get install -y libgpiod-dev
sudo apt-get install -y libi2c-dev
sudo apt-get install -y rsync
sudo apt-get install -y lxterminal
sudo apt-get install -y libglib2.0-bin
sudo apt-get install -y libgtk-3-dev
if [ -f ~/venv/bin/activate ]; then
    source ~/venv/bin/activate
    pip install rich==13.8.1
    pip install psutil
    pip install pyfiglet
else
    echo "Error: Virtual environment not found at ~/venv"
    exit 1
fi
echo "Install complete"
