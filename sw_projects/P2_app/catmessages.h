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
void HandleZZFA(void);


void HandleZZZD(void);                          // VFO freq down
void HandleZZZU(void);                          // VFO freq up
void HandleZZZE(void);                          // encoder
void HandleZZZP(void);                          // pushbutton
void HandleZZZI(void);                          // indicator
void HandleZZZS(void);                          // s/w version
void HandleZZTU(void);                          // TUNE
void HandleZZNA(void);                          // Noise Blanker


#endif  //#ifndef