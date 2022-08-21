//////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 1 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// version.h:
// print version information from FPGA registers
//
//////////////////////////////////////////////////////////////

#ifndef __version_h
#define __version_h

#include <stdint.h>



//
// prints version information from the registers
//
void PrintVersionInfo(void);


#endif