//////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 1 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// hwaccess.c:
// Hardware access to Saturn FPGA via PCI express
//
//////////////////////////////////////////////////////////////

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../common/debugaids.h"



//
// dump a memory buffer to terminal in hex
// should be a multiple of 16 bytes long!
//
void DumpMemoryBuffer(char* MemPtr, uint32_t Length)
{
	uint32_t ByteCntr;
  	uint32_t RowCntr;

	for (RowCntr=0; RowCntr < Length/16; RowCntr++)
	{
		printf("%04x   ", RowCntr*16);
		for (ByteCntr = 0; ByteCntr < 16; ByteCntr++)
			printf("%02x ", *MemPtr++);
		printf("\n");
	}
}


