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
#include "catmessages.h"
#include "cathandler.h"


//
// CAT handlers pick up their parameters from global values
// (this is done because then one jump table can be used for all)
// the parsed result will be in ParsedString, ParsedInt or ParsedBool as set in message table
//

//
// array of records. This must exactly match the enum ECATCommands in tiger.h
// and the number of commands defined here must be correct
// (not including the final eNoCommand)
// if there is no handler needed, set function pointer to NULL

SCATCommands GCATCommands[VNUMCATCMDS] = 
{
  {"ZZZD", eNum, 0, 99, 2, false, NULL},                        // VFO down
  {"ZZZU", eNum, 0, 99, 2, false, NULL},                        // VFO up
  {"ZZZE", eNum, 0, 999, 3, false, NULL},                       // encoder
  {"ZZZP", eNum, 0, 999, 3, false, NULL},                       // pushbutton
  {"ZZZI", eNum, 0, 999, 3, false, HandleZZZI},                 // indicator
  {"ZZZS", eNum, 0, 9999999, 7, false, HandleZZZS},             // s/w version
  {"ZZTU", eBool, 0, 1, 1, false, NULL},                        // tune
  {"ZZFA", eStr, 0, 0, 11, false, HandleZZFA},                  // VFO A frequency
  {"ZZXV", eNum, 0, 1023, 4, false, HandleZZXV},                // VFO status
  {"ZZUT", eBool, 0, 1, 1, false, HandleZZUT},                  // 2 tone test
  {"ZZYR", eBool, 0, 1, 1, false, HandleZZYR}                   // RX1/RX2 buttons
};


//
// ZZFA
// only really here for test - not used operationally
//
void HandleZZFA(void)
{
    printf("ZZFA: Frequency=%s\n", ParsedString);
}


//
// combined VFO status 
//
void HandleZZXV(void)                          // VFO status
{
    SetG2V2ZZXVState((uint32_t)ParsedInt);
//    printf("ZZXV: param=%04x\n", ParsedInt);
}


//
// 2 Tone test 
//
void HandleZZUT(void)                          // 2 tone test
{
    SetG2V2ZZUTState(ParsedBool);
    //printf("ZZUT: param=%04x\n", (int)ParsedBool);
}


//
// RX1/RX2
//
void HandleZZYR(void)                          // RX1/2
{
    SetG2V2ZZYRState(ParsedBool);
//    printf("ZZUT: param=%04x\n", (int)ParsedBool);
}


//
// product ID and version
//
void HandleZZZS(void)                          // ID
{
    SetG2V2ZZZSState((uint32_t)ParsedInt);
}


//
// Indicator settings
//
void HandleZZZI(void)                          // indicator
{
    SetG2V2ZZZIState((uint32_t)ParsedInt);
}