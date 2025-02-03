#!/bin/bash

#Optional navigation step
cd ~/github/Saturn/FPGA

#Get the lastest file based on version number using sort and tail
latest_file=$(ls saturnprimary*.bin | sort -V | tail -n 1)

#Output the latest file
echo "The latest FPGA firmware image file is: $latest_file"
echo "update using flashwriter app if needed"
