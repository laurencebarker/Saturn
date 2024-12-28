/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// serialport.h:
//
// handle simple access to serial port
//
//////////////////////////////////////////////////////////////

#ifndef __SERIALPORT_C
#define __SERIALPORT_C

#include <stdbool.h>

//
// define the potential types of serial device
//
typedef enum 
{
  eG2V2Panel,
  eG2V1PanelAdapter,
  eAriesATU
} ESerialDeviceType;


//
// open and set up a serial port for read/write access
//
int OpenSerialPort(char* DeviceName);


//
// send a string to the serial port
//
void SendStringToSerial(int Device, char* Message);

//
// function ot test whether any characters are present in the serial port
// return true if there are.
//
bool AreCharactersPresent(int Device);

//
// struct with settings for a serial reader thread
//
typedef struct
{
  int DeviceHandle;
  ESerialDeviceType Device;
  bool DeviceActive;
} TSerialThreadData;

//
// serial read thread
//
void G2V2PanelSerial(void *arg);


#endif