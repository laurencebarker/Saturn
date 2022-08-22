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
// OutDDCIQ.h:
//
// header: handle "outgoing DDC I/Q data" message
//
//////////////////////////////////////////////////////////////

#ifndef __OutDDCIQ_h
#define __OutDDCIQ_h


#include <stdint.h>
#include "../common/saturntypes.h"


#define VDDCPACKETSIZE 1444             // each DDC I/Qpacket


//
// protocol 2 handler for outgoing DDC I/Q data Packet from SDR
//
void *OutgoingDDCIQ(void *arg);


//
// interface calls to get commands from PC settings
//

//
// HandlerSetDDCEnabled(unsigned int DDC, bool Enabled)
// set whether an DDC is enabled
//
void HandlerSetDDCEnabled(unsigned int DDC, bool Enabled);


//
// HandlerSetDDCInterleaved(unsigned int DDC, bool Interleaved)
// set whether an DDC is interleaved
// this is called for odd DDCs, and if interleaved synchs to next lower number
// eg DDC3 can synch to DDC2
//
void HandlerSetDDCInterleaved(unsigned int DDC, bool Interleaved);


//
// HandlerSetP2SampleRate(unsigned int DDC, unsigned int SampleRate)
// sets the sample rate for a single DDC (used in protocol 2)
// allowed rates are 48KHz to 1536KHz.
//
void HandlerSetP2SampleRate(unsigned int DDC, unsigned int SampleRate);






#endif