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
// OutMicAudio.h:
//
// header: handle "outgoing microphone audio" message
//
//////////////////////////////////////////////////////////////

#ifndef __OutMicAudio_h
#define __OutMicAudio_h


#include <stdint.h>
#include "../common/saturntypes.h"


#define VMICPACKETSIZE 132              // microphone packet


//
// protocol 2 handler for outgoing microphone audio data Packet from SDR
//
void *OutgoingMicSamples(void *arg);


#endif