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
// 8 bit Codec register write over the AXILite bus via SPI
// using simple SPI writer IP
// given 7 bit register address and 8 bit data
// (the 9th, top data bit is always 0 for a write so only 8 useful bits)
//
void CodecRegisterWrite(uint32_t Address, uint32_t Data);



//
// 8 bit Codec register read over the AXILite bus via SPI
// using simple SPI writer IP
// given 7 bit register address
// note this function will work with the IP we've had for a while;
// but only transfers data using the new TLV320AIC3204 codec)
//
uint8_t CodecRegisterRead(uint32_t Address);

#endif