# Saturn
Saturn SDR project FPGA 

BIT files to program the configuration Flash EPROM can be found here. 

saturnfallback.bin: complete fallback image. DON'T program this unless you need to!
saturnprinaryxx.bin: primary config file for FPGA version XX. This should be programmed using flashwriter" as the PRIMARY image. 

Version history:


V25. 07/06/2025: Added drives to select HPF in TX path for future Saturn PCB. Does not affect behaviour with current PCB. 
V24. 20/05/2025: Cordic removed and replaced by original DDS. Cordic had slightly worse broadband noise performance. 
V23. 15/05/2025: experimental replacement of TX DDS by CORDIC derived from that in Orion. fixed I/Q amplitude for debug use set to 0.9 ampl from 1.0
V22. 18/04/2025: minor non functional change to TX DUC block design (results in the same code being generated)
V21. 05/04/2025: replaced codec SPI interface with new IP in readiness for '3204 replacement codec device
V20, 17/02/2025: added watchdog to cancel TX if client s/w does not service FIFOs for more that 2 seconds
V19, 26/11/2024: minor update
V18, 20/11/2024: introduced wideband data collection
V17: 20/6/2024: fixed edge rate sidetone added alongside the variable edge rate RF envelope
V15, 16: experimental NOT RECOMMENDED builds investigating TX composite noise
V14, 2/5/2024: maximum CW ramp length extended to 20ms. This is still an experimental release and **not recommended** for use yet.
V13, 1/4/2024: revised TXZ chain to reduce overall TX noise level. This is an experimental release and **not recommended** for use yet.
V12, Jan 9 2024:  Revised Alex SPI core with separate TX antenna bits to address CW keyer coupling energy to RX antennas
V11, 15 Dec 2023: added TUNE input from LDG ATU; changed reset timing for ALEX SPI output
V10, Sept 30 2023:FIFO depths increased; updated FIFO monitor IP
V9, Sept 29 2023: updated project to vivado 2023.1
V8, August 23 2023: changed FPGA to use the left data path from codec line input
V7, July 29 2023: Assert PTT out if CW keyer asserts PTT
V6, July 16 2023: DAC ALC ouptut now clocked at 122.88MHz.
V5, June 2 2023: fixed DDC6 sample rate issue
V4, April 11 2023: Fixed DC spike in DDC passbans
    Jan 25 2023: Added Iambic keyer.


Recommended build procedure
the build method using create_saturn_project.tcl is not recommended with newer versions of Vivado.
Instead, the design source tree from Vivado can now be checked into git, which is what we have done. 

1. Install Vivado 2023.1
2. Create a suitable folder: I recommend c:\xilinxdesigns\Saturn
3. do a git pull to copy the complete Saturn repository (https://github.com/laurencebarker/Saturn.git) into the folder (I use github desktop)
4. Run Vivado then open project file C:\xilinxdesigns\Saturn\FPGA\saturn_project\saturn_project.xpr
5. Wait patiently: it will take some time before the source files are listed in the Sources window.
6. Find design source file listed as saturn_top_i: saturn top (saturn_top.bd)
7. right click the file and select Create HDL wrapper. Allow Vivado to manage the file. 
8. click Generate Bitstream in the project manager window.
9. Wait patiently... this could take several hours the 1st time!
10. After that has completed, loci Generate Memory Configuration File from the Tools menu. There are instructions in the FPGA\documentation folder: Generating Configuration PROM file.docx 

