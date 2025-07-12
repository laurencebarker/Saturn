#!/bin/bash

# Script to install 

echo "Installing libraries..."
sudo apt-get install -y libgpiod-dev
sudo apt-get install -y libi2c-dev
sudo apt-get install -y rsync
sudo apt-get install -y lxterminal
sudo apt-get install -y libglib2.0-bin
if [ -f ~/venv/bin/activate ]; then
    source ~/venv/bin/activate
    pip install rich==14.0.0
    pip install psutil==7.0.0
    pip install pyfiglet
else
    echo "Error: Virtual environment not found at ~/venv"
    exit 1
fi
echo "Install complete"
