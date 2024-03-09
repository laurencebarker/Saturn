/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// catmessages.h:
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
#include "catmessages.h"
#include "cathandler.h"


//
// CAT handlers pick up their parameters from global values
// (this is done because then one jump table can be used for all)
// the parsed result will be in ParsedString, ParsedInt or ParsedBool as set in message table
//

//
// VFO A frequency 
//
void HandleZZFA(void)
{
    printf("eZZFA: Frequency = %s\n", ParsedString);
}


//
// VFO step down
//
void HandleZZZD(void)
{
    printf("eZZZD\n");
}


//
// VFO step up
//
void HandleZZZU(void)
{
    printf("eZZZU\n");
}


//
// encoder step
//
void HandleZZZE(void)
{
    printf("eZZZE\n");
}


//
// pushbutton event
//
void HandleZZZP(void)
{
    printf("eZZZP\n");
}


//
// set indicator
//
void HandleZZZI(void)
{
    printf("eZZZI\n");
}


//
// S/W version
//
void HandleZZZS(void)
{
    printf("eZZZS\n");
}


//
// TUNE
//
void HandleZZTU(void)
{
    printf("eZZTU\n");
}

//
// Noise blanker
//
void HandleZZNA(void)
{
    printf("eZZNA\n");
}
