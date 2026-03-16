#!/usr/bin/env bash
# build-xdma.sh
# Version: 1.0
# Laurence Barker G8NJJ

cd github/saturn/linuxdriver/xdma
sudo apt install linux-headers-rpi-v8

# build and install driver
sudo rmmod -s xdma
make
sudo make install
sudo modprobe xdma

#install udev rules file
sudo cp ../etc/udev/rules.d/* /etc/udev/rules.d

echo please restart before driver is active
