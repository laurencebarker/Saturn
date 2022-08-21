//////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 1 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// codecwrite.h:
// write to a codec register on the I2C bus
//
//////////////////////////////////////////////////////////////

#ifndef __codecwrite_h
#define __codecwrite_h



//
// 8 bit Codec register write over the AXILite bus via I2C
// given 7 bit register address and 9 bit data
//
void CodecRegisterWrite(unsigned int Address, unsigned int Data);


#endif