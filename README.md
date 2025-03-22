# Saturn
Saturn SDR project FPGA amd other files
This repository holds the source for the Xilinx Artix-7 FPGA created using Vivado

Current version create using Vivado 2023.1; you **must** use the same version of vivado.


The file structure is:

FPGA				FPGA design files
linuxdriver			source files for the device driver, patched from Xilinx AR65444
project_documentation		overall project level documentation
hardware			releasable information about the Saturn hardware (note the design is not open source)
sw_projects			software projects for Saturn
sw_tools			software tools including debugging tools
testing				project test resources
desktop                         desktop shortcuts to application files
scripts				shell scripts to update applications
rules				udev rules files


FPGA\sources
-coefficientfiles		.COE files for FIR filter coefficients and CW keyer ROM
-verilogmodules			various IP modules
-wrapper			holds the HDL wrapper for the block design

FPGA\constraints			holds the .XDC constraint files

FPGA\create_saturn_project.tcl	script to recreate the project

This script is not relocatable. We recommend you use the same directory structure we use. The TCL script will need to be edited if not.
open it in path: c:/xilinxdesigns/Saturn/FPGA          (case sensitive!)

To use this repository:
1. Install vivado 2023.1
2. Copy this repository to c:\xilinxdesigns\saturn
3. Open vivado and find the TCL command line
4. type: cd c:/xilinxdesigns/Saturn/FPGA
5. type: source create_saturn_project.tcl

A new xilinx project will be created in the subdirectory FPGA\saturn_project
if all goes well, select "generate bitstream" an the FPGA will be built

