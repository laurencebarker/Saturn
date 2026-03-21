#!/bin/bash
# find the latest FPGA flash file, and program it

# navigation step
cd ~/github/Saturn/FPGA

#Get the lastest file based on version number using sort and tail
latest_file=$(ls saturnprimary*.bin | sort -V | tail -n 1)

#Output the latest file
echo "The latest FPGA firmware image file is: $latest_file"
echo "calling programmer app"

~/github/Saturn/sw_tools/load-FPGA/load-FPGA -b $latest_file -v
#
echo "FPGA programming complete. Please power off and back on"



