/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 1 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// saturndrivers.h:
// header file. Drivers for minor IP cores
//
//////////////////////////////////////////////////////////////


#ifndef __saturndrivers_h
#define __saturndrivers_h

#include <stdint.h>
#include "../common/saturntypes.h"



//
// enum to describe an RX FIFO channel
//
typedef enum
{
	eDDC0_1,
	eDDC3_2,
	eDDC5_4,
	eDDC7_6,
	eDDC9_8
} EDDCSelect;





//
// void SetupFIFOMonitorChannel(uint32_t Monitor, uint32_t Channel, uint32_t Depth, bool IsWriteFIFO, bool EnableInterrupt);
//
// Setup a single FIFO monitor channel.
//   Monitor:			FIFO monitor number (0 to 3)
//   Channel:			IP core channel number (0 to 3)
//   Depth:				FIFO depth in words.
//   IsWriteFIFO:		true if a write FIFO (ie must not underflow)
//   EnableInterrupt:	true if interrupt generation enabled for overflows
//
void SetupFIFOMonitorChannel(uint32_t Monitor, uint32_t Channel, uint32_t Depth, bool IsWriteFIFO, bool EnableInterrupt);


//
// uint32_t ReadFIFOMonitorChannel(uint32_t Monitor, uint32_t Channel, bool* Overflowed);
//
// Read number of locations in a FIFO
//   Monitor:			FIFO monitor number (0 to 3)
//   Channel:			IP core channel number (0 to 3)
//   Overflowed:		true if an overflow has occurred. Reading clears the overflow bit.
//
uint32_t ReadFIFOMonitorChannel(uint32_t Monitor, uint32_t Channel, bool* Overflowed);



//
// void EnableRXFIFOChannels(EDDCSelect DDCNum, bool Enabled, bool Interleaved);
//
// Enable or disable sample stream from a DDC pair.
// If interleaved, one sample stream emerges for both DDCs
// To change between interleaved or not:
// 1. Disable sample flow;
// 2. clear out FIFO;
// 3. select new mode then re-enable
// 
// If there is ever a FIFO overflow, that process will need to be followed too
// otherwise there is ambiguity whether the samples left begin with even or odd DDC
//
void EnableRXFIFOChannels(EDDCSelect DDCNum, bool Enabled, bool Interleaved);


//
// reset a DDC FIFO (note they are reset on DDC pairs)
//
void ResetDDCFIFO(EDDCSelect DDCNum);


#endif
