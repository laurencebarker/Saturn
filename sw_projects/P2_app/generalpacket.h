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
// generalpacket.h:
//
// header: handle "general packet to SDR" message
//
//////////////////////////////////////////////////////////////

#ifndef __generalpacket_h
#define __generalpacket_h


#include <stdint.h>
#include "../common/saturntypes.h"

extern bool HW_Timer_Enable;

//
// protocol 2 handler for General Packet to SDR
// parameter is a pointer to the UDP message buffer.
// copy port numbers to port table, 
// then create listener threads for incoming packets & senders foroutgoing
//
int HandleGeneralPacket(uint8_t *PacketBuffer);



#endif