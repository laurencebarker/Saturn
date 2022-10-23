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
// void SetupFIFOMonitorChannel(EDMAStreamSelect Channel, bool EnableInterrupt);
//
// Setup a single FIFO monitor channel.
//   Channel:			IP channel number (enum)
//   EnableInterrupt:	true if interrupt generation enabled for overflows
//
void SetupFIFOMonitorChannel(EDMAStreamSelect Channel, bool EnableInterrupt)
{
	uint32_t Address;							// register address
	uint32_t Data;								// register content

	Address = VADDRFIFOMONBASE + 4 * Channel + 0x10;			// config register address
	Data = DMAFIFODepths[(int)Channel];							// memory depth
	if ((Channel == eTXDUCDMA) || (Channel == eSpkCodecDMA))	// if a "write" FIFO
		Data += 0x40000000;						// bit 30 
	if (EnableInterrupt)
		Data += 0x80000000;						// bit 31
	RegisterWrite(Address, Data);
}



//
// uint32_t ReadFIFOMonitorChannel(EDMAStreamSelect Channel, bool* Overflowed);
//
// Read number of locations in a FIFO
//   Channel:			IP core channel number (enum)
//   Overflowed:		true if an overflow has occurred. Reading clears the overflow bit.
//
uint32_t ReadFIFOMonitorChannel(EDMAStreamSelect Channel, bool* Overflowed)
{
	uint32_t Address;							// register address
	uint32_t Data = 0;							// register content
	bool Overflow = false;

	Address = VADDRFIFOMONBASE + 4 * Channel;			// status register address
	Data = RegisterRead(Address);
	if (Data & 0x80000000)						// if top bit set, declare overflow
		Overflow = true;
	Data = Data & 0xFFFF;						// strip to 16 bits
	*Overflowed = Overflow;						// send out overflow result
	return Data;								// return 16 bit FIFO count
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
