the multiboot_address_table.tcl script is hard to run!

create both golden and primary images in SPI X1 mode

open a vivado console by getting a command window, then

cd c:\xilinx\vivado\2021.2\bin
vivado -mode tcl
cd c:/xilinxdesigns/Saturn/FPGA/multiboot_address_table
source multiboot_address_table.tcl


That runs the script in interactive mode

for Saturn
enter:

spi
1
61
256
9730652




the results give load addresses:
0x00000000    golden image
0x0097FC00    timer 1
0x00980000    multiboot image
0x01300000    timer 2

And the images should NOT be compressed

Then create the pronfile by running

write_cfgmem -format bin -size 32 -interface SPIx1 -loadbit "up 0x00000000 saturn_top_wrapper_golden.bit up 0x00980000 saturn_top_wrapper.bit" -loaddata "up 0x0097FC00 timer1.bin  up 0x01300000 timer2.bin" saturngolden.bin -force