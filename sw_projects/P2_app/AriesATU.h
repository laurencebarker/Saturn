/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// AriesATU.h:
//
// interface the Aries ATU
//
//////////////////////////////////////////////////////////////

#ifndef __AriesATU_h
#define __AriesATU_h

#include "../common/saturntypes.h"
#include <stdbool.h>
#include <stdint.h>


extern bool AriesATUActive;


//
// function to initialise a connection to the  ATU; call if selected as a command line option
//
void InitialiseAriesHandler(void);

//
// function to shutdown a connection to the  ATU; call if selected as a command line option
//
void ShutdownAriesHandler(void);

//
// receive ZZZS state
// this has already been decoded by the CAT handler
//
void SetAriesZZZSState(uint8_t ProductID, uint8_t HWVersion, uint8_t SWID);

//
// see if serial device belongs to an Aries open serial port
// return true if this handle belongs to Aries ATU
//
bool IsAriesSerial(uint32_t Handle);

//
// receive a ZZZP message from Aries
//
void HandleAriesZZZPMessage(uint32_t Param);

//
// receive a ZZOX tune success message from Aries
//
void HandleAriesZZOXMessage(bool Param);

//
// receive a ZZOZ erase success message from Aries
//
void HandleAriesZZOZMessage(bool Param);

//
// set TX frequency from SDR App
//
void SetAriesTXFrequency(uint32_t Newfreq);

//
// set Alex TX word from SDR App
//
void SetAriesAlexTXWord(uint16_t Word);

//
// set Alex RX word from SDR App
//
void SetAriesAlexRXWord(uint16_t Word);

//
// handle ATU button press on the G2V2 front panel
// State = 0: released; 1: pressed; 2: long pressed
//
void HandleATUButtonPress(uint8_t Event);

#endif