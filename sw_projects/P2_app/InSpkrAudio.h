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
// InSpkrAudio.h:
//
// header: handle "incoming speaker audio" message
//
//////////////////////////////////////////////////////////////

#ifndef __InSpkrAudio_h
#define __InSpkrAudio_h


#include <stdint.h>
#include "saturntypes.h"


#define VSPEAKERAUDIOSIZE 260           // speaker audio packet


//
// protocol 2 handler for incoming speaker audio data Packet to SDR
//
void *IncomingSpkrAudio(void *arg);             // listener thread


#endif