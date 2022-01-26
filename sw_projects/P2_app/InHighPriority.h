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
// InHighPriority.h:
//
// header: handle "incoming high priority" message
//
//////////////////////////////////////////////////////////////

#ifndef __InHighPriority_h
#define __InHighPriority_h


#include <stdint.h>
#include "saturntypes.h"


#define VHIGHPRIOTIYTOSDRSIZE 1444      // high priority packet to SDR


//
// protocol 2 handler for incoming high priority Packet to SDR
//
void *IncomingHighPriority(void *arg);          // listener thread


#endif