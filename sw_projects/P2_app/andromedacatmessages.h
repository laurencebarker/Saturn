/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// andromedacatmessages.h:
//
// handle incoming CAT messages
//
//////////////////////////////////////////////////////////////

#ifndef __andromedacatmessages_h
#define __andromedacatmessages_h


//
// make VFO encoder message
//
void MakeVFOEncoderCAT(int8_t Steps);

//
// make ordinary encoder message
//
void MakeEncoderCAT(int8_t Steps, uint8_t Encoder);

//
// make pushbutton message
// scancode: 1-11 (odd only, encoder); 21-28 (menu softkey); or 29-99 (other button)
// Event = 0: release; 1: press; 2: longpress
void MakePushbuttonCAT(uint8_t ScanCode, uint8_t Event);

//
// makeproductversionCAT
// create a ZZZS Message
//
void MakeProductVersionCAT(uint8_t ProductID, uint8_t HWVersion, uint8_t SWVersion);


#endif  //#ifndef