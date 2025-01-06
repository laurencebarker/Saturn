/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// g2v2panel.h:
//
// interface G2V2 front panel using I2C
//
//////////////////////////////////////////////////////////////

#ifndef __G2V2PANEL_h
#define __G2V2PANEL_h

#include <stdbool.h>
#include <stdint.h>



//
// function to initialise a connection to the G2 V2 front panel; call if selected as a command line option
//
void InitialiseG2V2PanelHandler(void);


//
// function to check if panel is present. 
// file can be left open if "yes".
//
bool CheckG2V2PanelPresent(void);


//
// function to shutdown a connection to the G2 front panel; call if selected as a command line option
//
void ShutdownG2V2PanelHandler(void);

//
// receive ZZUT state
//
void SetG2V2ZZUTState(bool NewState);


//
// receive ZZYR state
//
void SetG2V2ZZYRState(bool NewState);


//
// receive ZZXV state
//
void SetG2V2ZZXVState(uint32_t NewState);

//
// receive ZZZS state
//
void SetG2V2ZZZSState(uint8_t ProductID, uint8_t HWVersion, uint8_t SWID);

//
// receive ZZZI state
//
void SetG2V2ZZZIState(uint32_t Param);

//
// receive a ZZZP message from front panel
//
void HandleG2V2ZZZPMessage(uint32_t Param);

//
// see if serial device belongs to a front panel open serial port
// return true if this handle belongs to a front panel
//
bool IsFrontPanelSerial(uint32_t Handle);

//
// set ATU LED states
// bool true if lit.
// safe to call if the thread isn't active, because it just sets states.
//
void SetATULEDs(bool GreenLED, bool RedLED);

#endif      // file sentry