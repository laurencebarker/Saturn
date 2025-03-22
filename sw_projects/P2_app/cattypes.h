/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// cattypes.h:
//
// define common types needed for CAT message handling
//
//////////////////////////////////////////////////////////////

#ifndef __cattypes_h
#define __cattypes_h


//
// enum for type of CAT message decoded; established by parsing the incoming message
//
typedef enum
{
  eNone,                          // no parameter
  eBool,                          // boolean parameter
  eNum,                           // numeric parameter     
  eStr                            // string parameter
}ERXParamType;




#endif