/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// frontpanelhandler.h:
//
// handle interface to front panel controls
//
//////////////////////////////////////////////////////////////

#ifndef __frontpanelhandler_h
#define __frontpanelhandler_h


//
// function to initialise a connection to the front panel; call if selected as a command line option
// establish which if any front panel is attached, and get it set up.
//
void InitialiseFrontPanelHandler(void);


#endif  //#ifndef