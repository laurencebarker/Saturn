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
// InDUCIQ.h:
//
// header: handle "incoming DUC I/Q" message
//
//////////////////////////////////////////////////////////////

#ifndef __InDUCIQ_h
#define __InDUCIQ_h


#include <stdint.h>
#include "../common/saturntypes.h"


#define VDUCIQSIZE 1444                 // TX DUC I/Q data packet


//
// protocol 2 handler for incoming DUC I/Q data Packet to SDR
//
void *IncomingDUCIQ(void *arg);                 // listener thread

static void transferIQSamples_SIMD(const uint8_t* UDPInBuffer, uint8_t* IQBasePtr, int DMAWritefile_fd);
static void transferIQSamples_generic(const uint8_t* UDPInBuffer, uint8_t* IQBasePtr, int DMAWritefile_fd);
static void transferIQSamples(const uint8_t* UDPInBuffer, uint8_t* IQBasePtr, int DMAWritefile_fd);


//
// HandlerSetEERMode (bool EEREnabled)
// enables amplitude restoration mode. Generates envelope output alongside I/Q samples.
// NOTE hardware does not properly support this yet!
// TX FIFO must be empty. Stop multiplexer; set bit; restart
// 
void HandlerSetEERMode(bool EEREnabled);

#endif