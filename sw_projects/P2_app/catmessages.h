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



//
// firstly an enumerated list of all of the CAT commands
// ordered as per documentation, not alphabetically!
// this list must match exactly the table GCATCommands
//
#define VNUMCATCMDS 11

typedef enum 
{
  eZZZD,                          // VFO steps down
  eZZZU,                          // VFO steps up
  eZZZE,                          // other encoder
  eZZZP,                          // pushbutton
  eZZZI,                          // indicator
  eZZZS,                          // s/w version
  eZZTU,                          // tune
  eZZFA,
  eZZXV,
  eZZUT,
  eZZYR,
  eNoCommand                      // this is an exception condition
}ECATCommands;




//
// VFO A frequency 
//
void HandleZZFA(void);                          // frequency

//
// combined VFO status 
//
void HandleZZXV(void);                          // VFO status

//
// 2 Tone test 
//
void HandleZZUT(void);                          // 2 tone test

//
// RX1/RX2
//
void HandleZZYR(void);                          // RX1/2

//
// product ID and version
//
void HandleZZZS(void);                          // ID

//
// Indicator settings
//
void HandleZZZI(void);                         // indicator

#endif  //#ifndef