#!/bin/bash
# find the latest FPGA flash file, and program it
echo "finding current and avaiable FPGA versions:"

# navigate to FPGA folder:
cd ~/github/Saturn/FPGA

# get the latest file name based on version number using sort and tail
latest_file=$(ls saturnprimary*.bin | sort -V | tail -n 1)

# get the current version by reading back from FPGA:
current_file=$(~/github/Saturn/sw_tools/FPGAVersion/FPGAVersion)

# determine the version number by clipping the numerical parts:
# remove first part of filename to get a string like "27.bin"
available_vnumber_start=${latest_file:18}
available_vnumber=$(echo "$available_vnumber_start" | tr -d -c 0-9)

current_vnumber=${current_file:24}
echo "comparing versions"
echo "The available FPGA code: $available_vnumber"
echo "The currently programmed FPGA version: $current_vnumber"

if [[ "$available_vnumber" == "$current_vnumber" ]]
then
echo "FPGA version is already up to date"
else
echo "calling programmer app with file: $latest_file"
~/github/Saturn/sw_tools/load-FPGA/load-FPGA -b $latest_file -v
echo "FPGA programming complete. Please power off and back on"
fi





