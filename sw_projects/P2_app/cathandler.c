/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// cathandler.c
//
// interpret and generate CAT messages to cmmmunicate over TCP/IP with remote client
// Thetis accepts 1 CAT command per packet, and sends one response per packet
//
//////////////////////////////////////////////////////////////

#include "threaddata.h"
#include <stdint.h>
#include <errno.h>
#include <stdlib.h>
#include <stddef.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <sys/time.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <pthread.h>

#include "../common/saturnregisters.h"
#include "../common/saturndrivers.h"
#include "../common/hwaccess.h"
#include "../common/debugaids.h"
#include "cathandler.h"
#include "catmessages.h"
#include "serialport.h"



bool CATPortAssigned;                       // true if CAT set up and active
int CATPort;
bool ThreadActive = false;                  // true while CAT thread running
bool SignalThreadEnd = false;               // asserted to terminate thread
pthread_t CATThread;                        // thread reads/writes CAT commands



#define VNUMOPSTRINGS 16                    // size of output queue
#define VOPSTRSIZE 40                       // size of each string in queue
//
// CAT output buffer
//
char OutputStrings[VNUMOPSTRINGS] [VOPSTRSIZE];
int CATWritePtr = 0;                        // pointer to next string to write
int CATReadPtr = 0;                         // pointer to next string to read


extern SCATCommands GCATCommands[];



//
// lookup initial divisor from number of digits
// (for local numerical conversion)
//
long DivisorTable[] =
{
  0L,                                                    // not used
  1L,                                                    // 1 digit - already have units
  10L,                                                   // 2 digits - tens is first
  100L,                                                  // 3 digits - hundreds is 1st
  1000L,                                                 // 4 digits - thousands is 1st
  10000L,                                                // 5 digits - ten thousands is 1st
  100000L,                                               // 6 digits - hundred thousands
  1000000L,                                              // millions
  10000000L,                                             // 10 millions
  100000000L,                                            // 100 millions
  1000000000L,                                           // 1000 millions
  10000000000L,                                          // 10000 millions
  100000000000L,                                         // 100000 millions
  1000000000000L,                                        // 1000000 millions
  10000000000000L                                        // 10000000 millions
};






// this array holds a 32 bit representation of the CAT command
// to so a compare in a single test
unsigned long GCATMatch[VNUMCATCMDS];


//
// helper: categorise character as lower case
// (replaces Arduino function)
//
bool isLowerCase(char ch)
{
  bool Result = false;
  if((ch>='a') && (ch <='z'))
    Result = true;
  return Result;
}


//
// helper: categorise character as numeric
// (replaces Arduino function)
//
bool isDigit(char ch)
{
  bool Result = false;
  if((ch>='0') && (ch <='9'))
    Result = true;
  return Result;
}



//
// Make32BitStr
// simply a 4 char CAT command in a single 32 bit word for easy compare
//
unsigned long Make32BitStr(char* Input)
{
  unsigned long Result;
  byte CharCntr;
  char Ch;
  
  Result = 0;
  for(CharCntr=0; CharCntr < 4; CharCntr++)
  {
    Ch = Input[CharCntr];                                           // input character
    if (isLowerCase(Ch))                                             // force lower case to upper case
      Ch -= 0x20;
    Result = (Result << 8) | Ch;
  }
  return Result;
}



//
// helper: constrain the size of a number
// (replaces Arduino function)
//
int constrain(int Value, int Lower, int Upper)
{
  int Result = Value;

  if (Value < Lower)
    Result = Lower;
  if (Value > Upper)
    Result = Upper;
  return Result;
}



//
// initialise CAT handler
// load up the match strings with either valid commands or debug commands
//
void InitCATHandler()
{
  int CmdCntr;
  unsigned long MatchWord;

// initialise the matching 32 bit words to hold a version of each CAT command
  for(CmdCntr=0; CmdCntr < VNUMCATCMDS; CmdCntr++)
  {
    MatchWord = Make32BitStr(GCATCommands[CmdCntr].CATString);
    GCATMatch[CmdCntr] = MatchWord;
  }
  CATPort = 0;                        // set port not assigned
  CATPortAssigned = false;
}




//
// helper function
// returns true of the value found would be a legal character in a signed int, including the signs
//
bool isNumeric(char ch)
{
  bool Result = false;

  if (isDigit(ch))
    Result = true;
  else if ((ch == '+') || (ch == '-'))
    Result = true;

  return Result;
}


//
// ParseCATCmd()
// Parse a single command in the local input buffer
// process it if it is a valid command
//
void ParseCATCmd(char* Buffer,  int Source)
{
  int CharCnt;                              // number of characters in the buffer (same as length of string)
  unsigned long MatchWord;                  // 32 bit compressed input cmd
  ECATCommands MatchedCAT = eNoCommand;     // CAT command we've matched this to
  int CmdCntr;                              // counts CAT commands
  SCATCommands* StructPtr;                  // pointer to structure with CAT data
  ERXParamType ParsedType;                  // type of parameter actually found
  int ByteCntr;
  char ch;
  bool ValidResult = true;                  // true if we get a valid parse result
  bool ParsedBool;                            // if a bool expected, it goes here
  long ParsedInt;                             // if int expected, it goes here
  char ParsedString[20];                      // if string expected, it goes here

  void (*HandlerPtr)(int SourceDevice, ERXParamType HasParam, bool BoolParam, int NumParam, char* StringParam); 
  
  CharCnt = strlen(Buffer) - 1;
//
// CharCnt holds the input string length excluding the terminating null and excluding the semicolon
// test minimum length for a valid CAT command: ZZxx; plus terminating 0
//
  if (CharCnt < 4)
    ValidResult = false;
  else
  {
    MatchWord = Make32BitStr(Buffer);
    for (CmdCntr=0; CmdCntr < VNUMCATCMDS; CmdCntr++)         // loop thro commands we recognise
    {
      if (GCATMatch[CmdCntr] == MatchWord)
      {
        MatchedCAT = (ECATCommands)CmdCntr;                           // if a match, exit loop
        StructPtr = GCATCommands + (int)CmdCntr;
        break;
      }
    }
    if(MatchedCAT == eNoCommand)                                      // if no match was found
      ValidResult = false;
    else
    {
//
// we have recognised a 4 char ZZnn command that is terminated by a semicolon
// now we need to process the parameter bytes (if any) in the middle
// the CAT structs have the required information
// any parameter starts at position 4 and ends at (charcnt-1)
//
      if (CharCnt == 4)
        ParsedType=eNone;
      else
      {
//
// strategy is: first copy just the param to a string
// if required type is not a string, parse to a number
// then if required type is bool, check the value
//        
        ParsedType = eStr;
        for(ByteCntr = 0; ByteCntr < (CharCnt-4); ByteCntr++)
          ParsedString[ByteCntr] = Buffer[ByteCntr+4];
        ParsedString[CharCnt - 4] = 0;
// now see if we want a non string type
// for an integer - use atoi, but see if 1st character is numeric, + or -
        if (StructPtr->RXType != eStr)
        {
          ch=ParsedString[0];
          if (isNumeric(ch))
          {
            ParsedType = eNum;
            ParsedInt = atoi(ParsedString);
// finally see if we need a bool
            if (StructPtr->RXType == eBool)
            {
              ParsedType = eBool;
              if (ParsedInt == 1)
                ParsedBool = true;
              else
                ParsedBool = false;
            }
          }
          else
          {
            ParsedType = eNone;
            ValidResult = false;            
          }
        }
      }
    }
  }
  if (ValidResult == true)
  {
    // debug: print the match found
//    printf("match= %s ; parameter=", GCATCommands[MatchedCAT].CATString);
//    switch(ParsedType)
//    {
//      case eStr: 
//        printf("%s\n", ParsedString);
//        break;
//      case eNum:
//        ParsedInt = constrain(ParsedInt, StructPtr->MinParamValue, StructPtr->MaxParamValue);
//        printf("%ld\n", ParsedInt);
//        break;
//      case eBool:
//        if(ParsedBool == true)
//          printf("true\n");
//        else
//          printf("false\n");
//        break;
//      case eNone:
//        printf("\n");
//        break;
//    }
    HandlerPtr = GCATCommands[MatchedCAT].handler;
    if(HandlerPtr != NULL)
      (*HandlerPtr)(Source, ParsedType, ParsedBool, ParsedInt, ParsedString);
  }
  else
  {
//    Serial.print("Parse Error - cmd= ");
//    Serial.println(GCATInputBuffer);
  }
}

//
// get CAT o/p buffer Used
//
int GetCATOPBufferUsed(void)
{
  int Used;                           // number of occupied locations
  Used = CATWritePtr - CATReadPtr;
  if(Used < 0)
    Used +=  + VNUMOPSTRINGS;
  return Used;
}


//
// send a CAT command
// only attempt send if an active CAT port exists
//
void SendCATMessage(char* Msg)
{
  if((GetCATOPBufferUsed() <= (VNUMOPSTRINGS - 1))&&(CATPortAssigned == true))
  {
    strcpy(OutputStrings[CATWritePtr++], Msg);
    printf("Sent CAT msg %s\n", Msg);                       // debug
    if(CATWritePtr >= VNUMOPSTRINGS)
      CATWritePtr = 0;
  }
}



//
// helper to append a string with a character
//
void Append(char* s, char ch)
{
  byte len;

  len = strlen(s);
  s[len++] = ch;
  s[len] = 0;
}




//
// create CAT message:
// this creates a "basic" CAT command with no parameter
// (for example to send a "get" command)
// Device = -1 for CAT port, else a serial device with this file ID
//
void MakeCATMessageNoParam(int Device, ECATCommands Cmd)
{
  char Output[VOPSTRSIZE];                                // TX CAT msg buffer
  SCATCommands* StructPtr;

  StructPtr = GCATCommands + (int)Cmd;
  strcpy(Output, StructPtr->CATString);
  strcat(Output, ";");
  if(Device < 0)
    SendCATMessage(Output);
  else
    SendStringToSerial(Device, Output);
}



//
// make a CAT command with a numeric parameter
// Device = -1 for CAT port, else a serial device with this file ID
//
void MakeCATMessageNumeric(int Device, ECATCommands Cmd, long Param)
{
  char Output[VOPSTRSIZE];                                // TX CAT msg buffer
  byte CharCount;                  // character count to add
  unsigned long Divisor;           // initial divisor to convert to ascii
  unsigned long Digit;             // decimal digit found
  char ASCIIDigit;
  SCATCommands* StructPtr;

  StructPtr = GCATCommands + (int)Cmd;
  strcpy(Output, StructPtr->CATString);
  CharCount = StructPtr->NumParams;
//
// clip the parameter to the allowed numeric range
//
  if (Param > StructPtr->MaxParamValue)
    Param = StructPtr->MaxParamValue;
  else if (Param < StructPtr->MinParamValue)
    Param = StructPtr->MinParamValue;
//
// now add sign if needed
//
  if (StructPtr -> AlwaysSigned)
  {
    if (Param < 0)
    {
      strcat(Output, "-");
      Param = -Param;                   // make positive
    }
    else
      strcat(Output, "+");
    CharCount--;
  }
  else if (Param < 0)                   // not always signed, but neg so it needs a sign
  {
      strcat(Output, "-");
      Param = -Param;      
      CharCount--;                      // make positive
  }
//
// we now have a positive number to fit into <CharCount> digits
// pad with zeros if needed
//
  Divisor = DivisorTable[CharCount];
  while (Divisor > 1)
  {
    Digit = Param / Divisor;                  // get the digit for this decimal position
    ASCIIDigit = (char)(Digit + '0');         // ASCII version - and output it
    Append(Output, ASCIIDigit);
    Param = Param - (Digit * Divisor);        // get remainder
    Divisor = Divisor / 10;                   // set for next digit
  }
  ASCIIDigit = (char)(Param + '0');           // ASCII version of units digit
  Append(Output, ASCIIDigit);
  strcat(Output, ";");
  if(Device < 0)
    SendCATMessage(Output);
  else
    SendStringToSerial(Device, Output);
}


//
// make a CAT command with a bool parameter
// Device = -1 for CAT port, else a serial device with this file ID
//
void MakeCATMessageBool(int Device, ECATCommands Cmd, bool Param) 
{
  char Output[VOPSTRSIZE];                                // TX CAT msg buffer
  SCATCommands* StructPtr;

  StructPtr = GCATCommands + (byte)Cmd;
  strcpy(Output, StructPtr->CATString);               // copy the base message
  if (Param)
    strcat(Output, "1;");
  else
    strcat(Output, "0;");
  if(Device < 0)
    SendCATMessage(Output);
  else
    SendStringToSerial(Device, Output);
}



//
// make a CAT command with a string parameter
// the string is truncated if too long, or padded with spaces if too short
// Device = -1 for CAT port, else a serial device with this file ID
//
void MakeCATMessageString(int Device, ECATCommands Cmd, char* Param) 
{
  char Output[VOPSTRSIZE];                                // TX CAT msg buffer
  byte ParamLength, ReqdLength;                        // string lengths
  SCATCommands* StructPtr;
  byte Cntr;

  StructPtr = GCATCommands + (byte)Cmd;
  ParamLength = strlen(Param);                        // length of input string
  ReqdLength = StructPtr->NumParams;                  // required length of parameter "nnnn" string not including semicolon
  
  strcpy(Output, StructPtr->CATString);               // copy the base message
  if(ParamLength > ReqdLength)                        // if string too long, truncate it
    Param[ReqdLength]=0; 
  strcat(Output, Param);                              // append the string
//
// now see if we need to pad
//
  if (ParamLength < ReqdLength)
  for (Cntr=0; Cntr < (ReqdLength-ParamLength); Cntr++)
    strcat(Output, " ");
//
// finally terminate and send  
//
  strcat(Output, ";");                                // add the terminating semicolon
  if(Device < 0)
    SendCATMessage(Output);
  else
    SendStringToSerial(Device, Output);
}








// this runs as its own thread to send and receive CAT data
// thread initiated after a port number received
// will be instructed to stop & exit by SDRActive becoming false
// (connection to SDR client list so no port to make use of)
// this is called when a connection port available; create socket on entry.
//
void* CATHandlerThread(void *arg)
{
    bool ThreadError = false;
    int CATSocketid;                                 // socket to access internet
    struct sockaddr_in addr_cat;
    int ActiveCATPort;
    int ReadResult;
    char ReadBuffer[1024] = {0};
    char SendBuffer[1024] = {0};
    unsigned int TXMessageLength;
//    bool DebugMessageSent = false;

    //
    // loop, creating then using socket
    // written this way so that if the port changes, we can exit the processing loop & re-connect
    //
    while(!ThreadError && SDRActive && !SignalThreadEnd)
    {
      //
      // create socket for TCP/IP connection
      //
      printf("Creating CAT socket on port %d\n", CATPort);
      struct timeval ReadTimeout;                                       // read timeout
      int yes = 1;
      if((CATSocketid = socket(AF_INET, SOCK_STREAM, 0)) < 0)
      {
          perror("CAT socket fail");
          return NULL;
      }

    //
    // set 1ms timeout, and re-use any recently open ports
    //
      setsockopt(CATSocketid, SOL_SOCKET, SO_REUSEADDR, (void *)&yes , sizeof(yes));
      ReadTimeout.tv_sec = 0;
      ReadTimeout.tv_usec = 1000;
      setsockopt(CATSocketid, SOL_SOCKET, SO_RCVTIMEO, (void *)&ReadTimeout , sizeof(ReadTimeout));

    //
    // connect to destination port
    //
      addr_cat.sin_addr.s_addr = reply_addr.sin_addr.s_addr;
      addr_cat.sin_family = AF_INET;
      addr_cat.sin_port = htons(CATPort);
      ActiveCATPort = CATPort;
      printf("Connecting CAT socket to port %d\n", CATPort);

      if(connect(CATSocketid, (struct sockaddr *)&addr_cat, sizeof(struct sockaddr_in)) < 0)
      {
          perror("CAT connect");
          return NULL;
      }
      ThreadActive = true;
      CATPortAssigned = true;

      printf("connected to CAT\n");


      //
      // now loop; process read, write events
      // exit loop if port number changes
      //
      while(!ThreadError && SDRActive && !SignalThreadEnd && (ActiveCATPort == CATPort))    // thread main loop
      {
  //        ReadResult = read(CATSocketid, ReadBuffer, 1023);
          ReadResult = recv(CATSocketid, ReadBuffer, 1023, 0);
          if(ReadResult > 0)
          {
              ParseCATCmd(ReadBuffer, DESTTCPCATPORT);
              memset(ReadBuffer, 0, sizeof(ReadBuffer));
          }
          //
          // if there are CAT messages available, send them
          //
          while(GetCATOPBufferUsed() != 0)
          {
            TXMessageLength = strlen(OutputStrings[CATReadPtr]);
            strcpy(SendBuffer, OutputStrings[CATReadPtr++]);
            if(CATReadPtr >= VNUMOPSTRINGS)
              CATReadPtr = 0;
            send(CATSocketid, SendBuffer, TXMessageLength, 0);
          }

      }                                                       // end of thread main loop
      close(CATSocketid);
      ActiveCATPort = 0;
      CATPort = 0;                                            // set port not assigned
      CATPortAssigned = false;
    }
    ThreadActive = false;
    ThreadError = false;
    return NULL;
}


//
// function to setup a CAT port handler
// save port number, and create a thread if needed
// note this will be called a lot of times: every time a high priority command message received. 
// only process this if the port is not yet assigned
void SetupCATPort(int Port)
{
    if (CATPort == 0)
    {
        CATPort = Port;
        if((!ThreadActive) && SDRActive && (CATPort != 0))
        {

          if(pthread_create(&CATThread, NULL, CATHandlerThread, NULL) < 0)
          {
              perror("pthread_create CAT handler");
              return;
          }
          pthread_detach(CATThread);
        }
    }  
}


//
// function to shut down CAT handler
// only returns when shutdown is complete
// signal thread to shut down, then wait
//
void ShutdownCATHandler(void)
{
    SignalThreadEnd = true;
    while(ThreadActive)
        usleep(1000);
    SignalThreadEnd = false;
}


