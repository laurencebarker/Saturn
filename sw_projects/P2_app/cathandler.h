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


#include "../common/saturntypes.h"
#include "catmessages.h"

typedef unsigned char byte;                 // copy of an Arduino type

extern bool CATPortAssigned;                // true if CAT set up and active

//
// these are treated as global, and used by the message handlers
//
extern bool ParsedBool;                          // if a bool expected, it goes here
extern long ParsedInt;                            // if int expected, it goes here
extern char ParsedString[20];                    // if string expected, it goes here



typedef enum
{
  eNone,                          // no parameter
  eBool,                          // boolean parameter
  eNum,                           // numeric parameter     
  eStr                            // string parameter
}ERXParamType;



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
  void (*handler)(void);          // handler function; no param and no return value
} SCATCommands;



extern SCATCommands GCATCommands[];


//
// initialise CAT handler
// load up the match strings with either valid commands or debug commands
//
void InitCATHandler();

//
// create CAT message:
// this creates a "basic" CAT command with no parameter
// (for example to send a "get" command)
//
void MakeCATMessageNoParam(ECATCommands Cmd);


//
// make a CAT command with a numeric parameter
//
void MakeCATMessageNumeric(ECATCommands Cmd, long Param);


//
// make a CAT command with a bool parameter
//
void MakeCATMessageBool(ECATCommands Cmd, bool Param);


//
// make a CAT command with a string parameter
// the string is truncated if too long, or padded with spaces if too short
//
void MakeCATMessageString(ECATCommands Cmd, char* Param);


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
//
void ParseCATCmd(char* CATString);

//
// make a CAT command with a numeric parameter into the provided string
// (used to send messages to local panel)
//
void MakeCATMessageNumeric_Local(ECATCommands Cmd, long Param, char* Str);


#endif  //#ifndef