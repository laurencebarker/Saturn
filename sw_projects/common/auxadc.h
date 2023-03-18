//////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 1 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// auxadc.h:
// access on-chip voltage and temperature values
//
//////////////////////////////////////////////////////////////

#ifndef __auxadc_h
#define __auxadc_h

#include <stdint.h>



//
// prints temperature information
//
void PrintAuxADCInfo(void);


#endif