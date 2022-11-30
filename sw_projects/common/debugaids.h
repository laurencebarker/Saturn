//////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 1 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// debugaids.h:
// debugging support code
//
//////////////////////////////////////////////////////////////

#ifndef __debugaids_h
#define __debugaids_h

#include <stdint.h>


//
// dump a memory buffer to terminal in hex
// should be a multiple of 16 bytes long!
//
void DumpMemoryBuffer(char* MemPtr, uint32_t Length);


#endif