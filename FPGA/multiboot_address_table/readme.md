the multiboot_address_table.tcl script is hard to run!

open a vivado console by getting a command window, then

cd c:\xilinx\vivado\2021.2\bin
vivado -mode tcl
multiboot_address_table.tcl

That runs the script in interactive mode

for Saturn
enter:

spi
4
61
256
9730652




the results give load addresses:
0x00000000    golden image
0x0097FC00    timer 1
0x00980000    multiboot image
0x01300000    timer 2

And the images should NOT be compressed