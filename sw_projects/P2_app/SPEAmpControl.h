/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// SPEAmpControl.h:
//
// Kenwood TS-2000 CAT emulation for SPE Expert linear amplifiers.
// Enable with -e /dev/ttyUSBx (optional :baud suffix, default 9600).
//
//////////////////////////////////////////////////////////////

#ifndef __SPEAmpControl_h
#define __SPEAmpControl_h

#include <stdbool.h>
#include <stdint.h>

// true while the SPE amp shim is running
extern bool SPEAmpActive;


// open serial port and start CAT listener thread; PathAndBaud is "path" or "path:baud"
bool InitialiseSPEAmpHandler(const char *PathAndBaud);

// signal the listener thread to stop and wait for it to exit
void ShutdownSPEAmpHandler(void);

// update TX frequency from the DUC delta-phase word
void SetSPEAmpTXFrequency(uint32_t NewFreqDeltaPhase);

// update TX/RX state used in IF responses
void SetSPEAmpTXState(bool IsTX);


#endif  // __SPEAmpControl_h
