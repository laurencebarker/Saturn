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
// OutHighPriority.h:
//
// header: handle "outgoing high priority data" message
//
//////////////////////////////////////////////////////////////

#ifndef __OutHighPriority_h
#define __OutHighPriority_h


#include <stdint.h>
#include "saturntypes.h"


#define VHIGHPRIOTIYFROMSDRSIZE 60      // high priority packet from SDR


//
// protocol 2 handler for outgoing high priority data Packet from SDR
//
void *OutgoingHighPriority(void *arg);



#endif