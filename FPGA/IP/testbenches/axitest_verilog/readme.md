This is a Vivado 2019.2 testbench project for several AXI-Lite bus interface modules used in the project.

The modules are instantiated in the block design, then the testbench has the AXI test code that initiates read and write transactions.

The source file IP is in this root folder. After recreating the project though the "used" version will be embedded in the .srcs folder - see the file properties to find the location.

To recreate: run vivado 2019.2 and type:
cd e:/xilinxdesigns/saturn/FPGA/IP/testbenches/axitest_verilog
source recreate_axitest_verilog.tcl
