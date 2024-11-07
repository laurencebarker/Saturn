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
#include "../common/saturnregisters.h"
#include "../P2_app/InDUCIQ.h"


//
// void SetupFIFOMonitorChannel(EDMAStreamSelect Channel, bool EnableInterrupt);
//
// Setup a single FIFO monitor channel.
//   Channel:			IP channel number (enum)
//   EnableInterrupt:	true if interrupt generation enabled for overflows
//
void SetupFIFOMonitorChannel(EDMAStreamSelect Channel, bool EnableInterrupt);



//
// uint32_t ReadFIFOMonitorChannel(EDMAStreamSelect Channel, bool* Overflowed, bool* OverThreshold, bool* Underflowed,  unsigned int* Current);
//
// Read number of locations in a FIFO
// for a read FIFO: returns the number of occupied locations available to read
// for a write FIFO: returns the number of free locations available to write
//   Channel:			IP core channel number (enum)
//   Overflowed:		true if an overflow has occurred. Reading clears the overflow bit.
//   OverThreshold:		true if overflow occurred  measures by threshold. Cleared by read.
//   Underflowed:       true if underflow has occurred. Cleared by read.
//   Current:           number of locations occupied (in either FIFO type)
//
uint32_t ReadFIFOMonitorChannel(EDMAStreamSelect Channel, bool* Overflowed, bool* OverThreshold, bool* Underflowed, uint16_t* Current);

//
// reset a stream FIFO
// clears the FIFOs directly read ori written by the FPGA
//
void ResetDMAStreamFIFO(EDMAStreamSelect DDCNum);


//
// SetTXAmplitudeEER (bool EEREnabled)
// enables amplitude restoratino mode. Generates envelope output alongside I/Q samples.
// NOTE hardware does not properly support this yet!
// 
void SetTXAmplitudeEER(bool EEREnabled);


//
// uint32_t AnalyseDDCHeader(unit32_t Header, unit32_t** DDCCounts)
// parameters are the header read from the DDC stream, and
// a pointer to an array [DDC count] of ints
// the array of ints is populated with the number of samples to read for each DDC
// returns the number of words per frame, which helps set the DMA transfer size
//
uint32_t AnalyseDDCHeader(uint32_t Header, uint32_t* DDCCounts);


#endif
