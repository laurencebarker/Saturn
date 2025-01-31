/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// catmessages.c:
//
// handle incoming CAT messages
//
//////////////////////////////////////////////////////////////

#include "threaddata.h"
#include <stdint.h>
#include "../common/saturntypes.h"
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
#include "g2v2panel.h"
#include "AriesATU.h"
#include "catmessages.h"
#include "cathandler.h"


//
// CAT handlers pick up their parameters from global values
// (this is done because then one jump table can be used for all)
// the parsed result will be in ParsedString, ParsedInt or ParsedBool as set in message table
//



//
// ZZFA
// received from SDR client app
// only really here for test - not used operationally
//
void HandleZZFA(int SourceDevice, ERXParamType Type, __attribute__((unused)) bool BoolParam, __attribute__((unused)) int NumParam, char* StringParam)
{
    if((SourceDevice == DESTTCPCATPORT) && (Type == eStr))
        printf("ZZFA: Frequency=%s\n", StringParam);
}


//
// combined VFO status 
// received from SDR client app
//
void HandleZZXV(int SourceDevice, ERXParamType Type, __attribute__((unused)) bool BoolParam, int NumParam, __attribute__((unused)) char* StringParam)                          // VFO status
{
    if((SourceDevice == DESTTCPCATPORT) && (Type == eNum))
        SetG2V2ZZXVState((uint32_t)NumParam);
}


//
// 2 Tone test 
// received from SDR client app
//
void HandleZZUT(int SourceDevice, ERXParamType Type, bool BoolParam, __attribute__((unused)) int NumParam, __attribute__((unused)) char* StringParam)                          // 2 tone test
{
    if((SourceDevice == DESTTCPCATPORT) && (Type == eBool))
        SetG2V2ZZUTState(BoolParam);
}


//
// RX1/RX2
// received from SDR client app
//
void HandleZZYR(int SourceDevice, ERXParamType Type, bool BoolParam, __attribute__((unused)) int NumParam, __attribute__((unused)) char* StringParam)                          // RX1/2
{
    if((SourceDevice == DESTTCPCATPORT) && (Type == eBool))
        SetG2V2ZZYRState(BoolParam);
//    printf("ZZUT: param=%04x\n", (int)ParsedBool);
}


//
// product ID and version
// This handles a response from a local device (front panel, ATU etc)
// decode the message, and call appropriate handler
//
void HandleZZZS(__attribute__((unused)) int SourceDevice, __attribute__((unused)) ERXParamType Type, __attribute__((unused)) bool BoolParam, int NumParam, __attribute__((unused)) char* StringParam)                          // ID
{
    uint8_t SWID;
    uint8_t HWVersion;
    uint8_t ProductID;

    if(Type == eNum)
    {
        ProductID = NumParam / 100000;
        NumParam = NumParam % 100000;
        HWVersion = NumParam / 1000;
        SWID= NumParam % 1000;
        if((ProductID == 4) || (ProductID == 5))                // if G2V1 adater or G2V2
            SetG2V2ZZZSState(ProductID, HWVersion, SWID);
        else if(ProductID == 2)
            SetAriesZZZSState(ProductID, HWVersion, SWID);
    }
}


//
// Indicator settings
// received from SDR client app
//
void HandleZZZI(int SourceDevice, ERXParamType Type, bool __attribute__((unused)) BoolParam, int NumParam, __attribute__((unused)) char* StringParam)                          // indicator
{
    if((SourceDevice == DESTTCPCATPORT) && (Type == eNum))
        SetG2V2ZZZIState((uint32_t)NumParam);
}


//
// Pushbutton
// received from Aries or from Front Panel
// pass onto code for those devices
//
void HandleZZZP(int SourceDevice, __attribute__((unused)) ERXParamType Type, __attribute__((unused)) bool BoolParam, int NumParam, __attribute__((unused)) char* StringParam)                          // pushbutton
{
    if(IsFrontPanelSerial(SourceDevice))
        HandleG2V2ZZZPMessage(NumParam);
    else if (IsAriesSerial(SourceDevice))
        HandleAriesZZZPMessage(NumParam);
}


//
// erase tuning solutions: this sends result back to radio
// (when sent by Aries it only encodes a 0 or 1 "success" parameter, not the antenna number)
//
void HandleZZOZ(int SourceDevice, __attribute__((unused)) ERXParamType Type, bool BoolParam, __attribute__((unused)) int NumParam, __attribute__((unused)) char* StringParam)                          // ATU erase
{
    if (IsAriesSerial(SourceDevice))
        HandleAriesZZOZMessage(BoolParam);
}


//
// ATU tune success/fail
//
void HandleZZOX(int SourceDevice, __attribute__((unused)) ERXParamType Type, bool BoolParam, __attribute__((unused)) int NumParam, __attribute__((unused)) char* StringParam)                          // ATU success/fail
{
    if (IsAriesSerial(SourceDevice))
        HandleAriesZZOXMessage(BoolParam);
}



//
// TUNE active request
//
void HandleZZTU(__attribute__((unused)) int SourceDevice, __attribute__((unused)) ERXParamType Type, bool BoolParam, __attribute__((unused)) int NumParam, __attribute__((unused))char* StringParam)                          // ATU success/fail
{
    SetAriesTuneState(BoolParam);
}


//
// array of records. This must exactly match the enum ECATCommands in tiger.h
// and the number of commands defined here must be correct
// (not including the final eNoCommand)
// if there is no handler needed, set function pointer to NULL
// ***this must be at the end of the file after the handlers! ***
//
SCATCommands GCATCommands[VNUMCATCMDS] = 
{
  {"ZZZD", eNum, 0, 99, 2, false, NULL},                        // VFO down
  {"ZZZU", eNum, 0, 99, 2, false, NULL},                        // VFO up
  {"ZZZE", eNum, 0, 999, 3, false, NULL},                       // encoder
  {"ZZZP", eNum, 0, 999, 3, false, HandleZZZP},                 // pushbutton
  {"ZZZI", eNum, 0, 999, 3, false, HandleZZZI},                 // indicator
  {"ZZZS", eNum, 0, 9999999, 7, false, HandleZZZS},             // s/w version
  {"ZZTU", eBool, 0, 1, 1, false, HandleZZTU},                  // tune
  {"ZZFA", eStr, 0, 0, 11, false, HandleZZFA},                  // VFO A frequency
  {"ZZXV", eNum, 0, 1023, 4, false, HandleZZXV},                // VFO status
  {"ZZUT", eBool, 0, 1, 1, false, HandleZZUT},                  // 2 tone test
  {"ZZYR", eBool, 0, 1, 1, false, HandleZZYR},                  // RX1/RX2 buttons
  {"ZZFT", eStr, 0, 64000000, 11, false, NULL},                 // TX frequency (sent to Aries)
  {"ZZOA", eNum, 0, 3, 1, false, NULL},                         // RX antenna
  {"ZZOC", eNum, 0, 3, 1, false, NULL},                         // TX antenna
  {"ZZOV", eBool, 0, 1, 1, false, NULL},                        // ATU enable/disable
  {"ZZOX", eBool, 0, 1, 1, false, HandleZZOX},                  // ATU tune success/fail
  {"ZZOY", eBool, 0, 1, 1, false, NULL},                        // set ATU option
  {"ZZOZ", eNum, 0, 3, 1, false, HandleZZOZ}                    // erase tuning solutions (reply is 0/1 only: fail/success)
};
