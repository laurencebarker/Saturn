Command line FPGA flash programmer
can be used to program the primary or fallback images

This folder holds files reused from Xilinx SDK at https://github.com/Xilinx/embeddedsw. 



build instructions:

make


usage:
1. Generate bitstream in Vivado
2. Use Vivado to create a binary format prom file eg "prom.bin"
3. load-FPGA [-b binary file] [-f] [-v]
   Programming specification options
   -b: Data file to load (raw binary)
   -v: Verify after programming
   -f: program fallback image


