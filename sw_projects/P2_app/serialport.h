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
// port is opened and read performed by creating a thread
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
// send a string to the serial port
//
void SendStringToSerial(int Device, char* Message);


//
// struct with settings for a serial reader thread
//
typedef struct
{
  char PathName[120];               // device path name
  int DeviceHandle;                 // file device, returned from OS
  ESerialDeviceType Device;         // expected device type
  bool DeviceActive;                // true if device is active
  bool RequestID;                   // true if thread should request device ID using ZZZS;
  bool IsOpen;                      // true if file device is open
} TSerialThreadData;

//
// serial read thread
//
void CATSerial(void *arg);


#endif