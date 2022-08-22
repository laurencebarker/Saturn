/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 1 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// saturndrivers.c:
// Drivers for minor IP cores
//
//////////////////////////////////////////////////////////////


#include "../common/saturndrivers.h"
#include "../common/saturnregisters.h"
#include "../common/hwaccess.h"                   // low level access
#include <stdlib.h>                     // for function min()
#include <math.h>




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
void SetupFIFOMonitorChannel(uint32_t Monitor, uint32_t Channel, uint32_t Depth, bool IsWriteFIFO, bool EnableInterrupt)
{
	uint32_t Address;							// register address
	uint32_t Data;								// register content

	Address = FIFOMonitorAddresses[Monitor] + 4 * Channel + 0x10;			// config register address
	Data = Depth;
	if (IsWriteFIFO)
		Data += 0x40000000;						// bit 30 
	if (EnableInterrupt)
		Data += 0x80000000;						// bit 31
	RegisterWrite(Address, Data);
}



//
// uint32_t ReadFIFOMonitorChannel(uint32_t Monitor, uint32_t Channel, bool* Overflowed);
//
// Read number of locations in a FIFO
//   Monitor:			FIFO monitor number (0 to 3)
//   Channel:			IP core channel number (0 to 3)
//   Overflowed:		true if an overflow has occurred. Reading clears the overflow bit.
//
uint32_t ReadFIFOMonitorChannel(uint32_t Monitor, uint32_t Channel, bool* Overflowed)
{
	uint32_t Address;							// register address
	uint32_t Data = 0;							// register content
	bool Overflow = false;

	Address = FIFOMonitorAddresses[Monitor] + 4 * Channel;			// status register address
	Data = RegisterRead(Address);
	if (Data & 0x80000000)						// if top bit set, declare overflow
		Overflow = true;
	Data = Data & 0xFFFF;						// strip to 16 bits
	*Overflowed = Overflow;						// send out overflow result
	return Data;								// return 16 bit FIFO count
}



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
void EnableRXFIFOChannels(EDDCSelect DDCNum, bool Enabled, bool Interleaved)
{
	uint32_t Address;									// register address
	uint32_t Data;										// register content

	Address = DDCConfigRegs[2*(int)DDCNum];				// DDC config register address
	Data = RegisterRead(Address);						// read current content
	Data &= 0xFFFCFFFF;									// clear bits 16, 17
	if (Enabled)
		Data &= ~0x00020000;							// bit 17 
	if (Interleaved)
		Data &= ~0x00010000;							// bit 16
	RegisterWrite(Address, Data);						// write back
}


//
// reset a DDC FIFO
// these are reset in pairs, so resetting DDC0 also resets DDC1
//
void ResetDDCFIFO(EDDCSelect DDCNum)
{
	uint32_t Address;									// DDC register address
	uint32_t Data;										// DDC register content

	Address = DDCConfigRegs[2*(int)DDCNum];				// DDC config register address
	Data = RegisterRead(Address);						// read current content
	Data = Data & ~(1<<18);
	RegisterWrite(Address, Data);						// set reset bit to zero
	Data = Data | (1<<18);
	RegisterWrite(Address, Data);						// set reset bit to 1
}
