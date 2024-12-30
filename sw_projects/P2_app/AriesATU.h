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

#endif