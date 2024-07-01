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
// VFO A frequency 
//
void HandleZZFA(void);                          // frequency

//
// combined VFO status 
//
void HandleZZXV(void);                          // VFO status


#endif  //#ifndef