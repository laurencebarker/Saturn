# Saturn
Saturn SDR project FPGA 

BIT files to program the configuration Flash EPROM can be found here. 

saturnfallback.bin: complete fallback image. DON'T program this unless you need to!
saturnprinaryxx.bin: primary config file for FPGA version XX. This should ne programmed using flashwriter" as the PRIMARY iage. 

Version history:

V10, Sept 30 2023:FIFO depths increased; updated FIFO monitor IP
V9, Sept 29 2023: updated project to vivado 2023.1
V8, August 23 2023: changed FPGA to use the left data path from codec line input
V7, July 29 2023: Assert PTT out if CW keyer asserts PTT
V6, July 16 2023: DAC ALC ouptut now clocked at 122.88MHz.
V5, June 2 2023: fixed DDC6 sample rate issue
V4, April 11 2023: Fixed DC spike in DDC passbans
    Jan 25 2023: Added Iambic keyer.

