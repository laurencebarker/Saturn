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
// HandlerCheckDDCSettings()
// called when DDC settings have been changed. Check which DDCs are enabled, and sample rate.
//
void HandlerCheckDDCSettings(void);









#endif