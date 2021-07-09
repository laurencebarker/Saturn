This folder holds files reused from Xilinx SDK at https://github.com/Xilinx/embeddedsw. Some files were modified some weren't.


build instructions:



make


usage:
1. Generate bitstream in Vivado
2. Use Vivado to create a binary format prom file eg "prom.bin"
3. use command line to program ad address 0, with verify:

./spiload -a 0 -f prom.bin -v