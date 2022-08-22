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
// incomingDUCspecific.h:
//
// header: handle "DUC specific" message
//
//////////////////////////////////////////////////////////////

#ifndef __DUCspecific_h
#define __DUCspecific_h


#include <stdint.h>
#include "../common/saturntypes.h"


#define VDUCSPECIFICSIZE 60             // DUC specific packet


//
// protocol 2 handler for incoming DUC specific Packet to SDR
//
void *IncomingDUCSpecific(void *arg);           // listener thread


#endif