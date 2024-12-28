/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// cathandler.h:
//
// interpret and generate CAT messages to cmmmunicate over TCP/IP with remote client
//
//////////////////////////////////////////////////////////////

#ifndef __CAThandler_h
#define __CAThandler_h

#include "cattypes.h"
#include "../common/saturntypes.h"
#include "catmessages.h"

typedef unsigned char byte;                 // copy of an Arduino type

extern bool CATPortAssigned;                // true if CAT set up and active



//
// this struct holds a record to describe one CAT command
//
typedef struct 
{
  char* CATString;                // eg "ZZAR"
  ERXParamType RXType;            // type of parameter expected on receive
  long MinParamValue;             // eg "-999"
  long MaxParamValue;             // eg "9999"
  byte NumParams;                 // number of parameter bytes in a "set" command
  bool AlwaysSigned;              // true if the param version should always have a sign
  void (*handler)(int SourceDevice, ERXParamType HasParam, bool BoolParam, int NumParam, char* StringParam);          // handler function; no param and no return value
} SCATCommands;

extern SCATCommands GCATCommands[];

#define DESTTCPCATPORT -1                          // selects CAT Port as the destination


//
// initialise CAT handler
// load up the match strings with either valid commands or debug commands
//
void InitCATHandler();

//
// create CAT message:
// this creates a "basic" CAT command with no parameter
// (for example to send a "get" command)
// Device = -1 for CAT port, else a serial device with this file ID
//
void MakeCATMessageNoParam(int Device, ECATCommands Cmd);


//
// make a CAT command with a numeric parameter
// Device = -1 for CAT port, else a serial device with this file ID
//
void MakeCATMessageNumeric(int Device, ECATCommands Cmd, long Param);


//
// make a CAT command with a bool parameter
// Device = -1 for CAT port, else a serial device with this file ID
//
void MakeCATMessageBool(int Device, ECATCommands Cmd, bool Param);


//
// make a CAT command with a string parameter
// the string is truncated if too long, or padded with spaces if too short
// Device = -1 for CAT port, else a serial device with this file ID
//
void MakeCATMessageString(int Device, ECATCommands Cmd, char* Param);


//
// function to setup a CAT port handler
//
void SetupCATPort(int Port);

//
// function to shut down CAT handler
// only returns when shutdown is complete
//
void ShutdownCATHandler(void);

//
// send a CAT message to TCP/IP port
//
void SendCATMessage(char* CatString);

//
// parse a CAT command, and call appropriate handler
// message source provided so potentially different handlers can be used
//
void ParseCATCmd(char* CATString, int Source);


#endif  //#ifndef