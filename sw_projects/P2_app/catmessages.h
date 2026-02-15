/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// catmessages.h:
//
// handle incoming CAT messages
//
//////////////////////////////////////////////////////////////

#ifndef __catmessages_h
#define __catmessages_h

#include "cattypes.h"
#include <stdint.h>
//#include "cathandler.h"



//
// firstly an enumerated list of all of the CAT commands
// ordered as per documentation, not alphabetically!
// this list must match exactly the table GCATCommands
//
#define VNUMCATCMDS 21

typedef enum 
{
  eZZZA,                          // amplifier protection
  eZZZD,                          // VFO steps down
  eZZZU,                          // VFO steps up
  eZZZE,                          // other encoder
  eZZZP,                          // pushbutton
  eZZZI,                          // indicator
  eZZZS,                          // s/w version
  eZZTU,                          // tune
  eZZFA,                          // VFO A frequency
  eZZGA,                          // add device to list by guid
  eZZGR,                          // remove device from list by guid
  eZZXV,
  eZZUT,
  eZZYR,
  eZZFT,                          // TX frequency
  eZZOA,                          // RX antenna
  eZZOC,                          // TX antenna
  eZZOV,                          // ATU enable
  eZZOX,                          // ATU Tune success/fail
  eZZOY,                          // ATU options
  eZZOZ,                          // erase ATU tune solutions
  eNoCommand                      // this is an exception condition
}ECATCommands;


//
// makeproductversionCAT
// create a ZZZS Message
// DestDevice identifies where message should go (-1 = TCP/IP, else a serial handle)
//
void MakeProductVersionCAT(uint8_t ProductID, uint8_t HWVersion, uint8_t SWVersion, int DestDevice);



#endif  //#ifndef