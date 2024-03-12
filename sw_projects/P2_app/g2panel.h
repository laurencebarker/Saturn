/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// g2panel.h:
//
// interface G2 front panel using GPIO and I2C
//
//////////////////////////////////////////////////////////////

#ifndef __G2PANEL_h
#define __G2PANEL_h


//
// function to initialise a connection to the G2 front panel; call if selected as a command line option
//
void InitialiseG2PanelHandler(void);






#endif      // file sentry