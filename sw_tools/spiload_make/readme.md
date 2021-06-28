This folder holds files reused from Xilinx SDK at https://github.com/Xilinx/embeddedsw. Some files were modified some weren't.


build instructions:

1. install cmake

sudo apt install cmake


2. change to this folder and issues cmake commands

cd ~/github/saturn/sw_tools/spiload
cmake -B build/
cmake --build build/


the resulting executable will be in the /build folder.