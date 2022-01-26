/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
// derived from Pavel Demin code 
//
// incomingDDCspecific.h:
//
// header: handle "DDC specific" message
//
//////////////////////////////////////////////////////////////

#ifndef __DDCspecific_h
#define __DDCspecific_h


#include <stdint.h>
#include "saturntypes.h"


#define VDDCSPECIFICSIZE 1444           // DDC specific packet size in bytes


//
// protocol 2 handler for incoming DDC specific Packet to SDR
//
void *IncomingDDCSpecific(void *arg);           // listener thread


#endif