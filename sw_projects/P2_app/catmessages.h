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
//#include "cathandler.h"



//
// firstly an enumerated list of all of the CAT commands
// ordered as per documentation, not alphabetically!
// this list must match exactly the table GCATCommands
//
#define VNUMCATCMDS 18

typedef enum 
{
  eZZZD,                          // VFO steps down
  eZZZU,                          // VFO steps up
  eZZZE,                          // other encoder
  eZZZP,                          // pushbutton
  eZZZI,                          // indicator
  eZZZS,                          // s/w version
  eZZTU,                          // tune
  eZZFA,                          // VFO A frequency
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






#endif  //#ifndef