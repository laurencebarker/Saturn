/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// GanymedePAControl.h:
//
// interface the Ganymede PA controller
//
//////////////////////////////////////////////////////////////

#ifndef __GanymedeATU_h
#define __GanymedeATU_h

#include "../common/saturntypes.h"
#include <stdbool.h>
#include <stdint.h>


extern bool GanymedeActive;


//
// function to initialise a connection to the PA controller; call if selected as a command line option
//
void InitialiseGanymedeHandler(void);

//
// function to shutdown a connection to the PA controller; call if selected as a command line option
//
void ShutdownGanymedeHandler(void);

//
// receive ZZZS state
// this has already been decoded by the CAT handler
//
void SetGanymedeZZZSState(uint8_t ProductID, uint8_t HWVersion, uint8_t SWID);

//
// see if serial device belongs to a Ganymede open serial port
// return true if this handle belongs to Ganymede controller
//
bool IsGanymedeSerial(int Handle);

//
// receive a ZZZA message from Ganymede
// source device identified where message came from; -1 for TCP/IP port, else the serial handle
//
void HandleGanymedeZZZAMessage(uint32_t Param, int SourceDevice);


#endif