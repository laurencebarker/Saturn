/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// andromedacatmessages.h:
//
// make outgoing CAT messages
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
#include "andromedacatmessages.h"
#include "cathandler.h"



//
// make VFO encoder message
//
void MakeVFOEncoderCAT(int8_t Steps)
{
    if (Steps<0)
        MakeCATMessageNumeric(DESTTCPCATPORT, eZZZD, -Steps);
    else if(Steps > 0)
        MakeCATMessageNumeric(DESTTCPCATPORT, eZZZU, Steps);
}




//
// make ordinary encoder message
//
void MakeEncoderCAT(int8_t Steps, uint8_t Encoder)
{
    uint32_t CatParam;

    if(Steps > 0)
    {
        if (Steps > 9)                                  // limited to 9 steps
            Steps = 9;
        CatParam = (Encoder * 10) + Steps;
        MakeCATMessageNumeric(DESTTCPCATPORT, eZZZE, CatParam);
    }
    else if(Steps < 0)
    {
        Steps = -Steps;
        if (Steps > 9)                                  // limited to 9 steps
            Steps = 9;
        CatParam = (Encoder * 10) +500 + Steps;
        MakeCATMessageNumeric(DESTTCPCATPORT, eZZZE, CatParam);
    }
}




//
// make pushbutton message
// scancode: 1-11 (odd only, encoder); 21-28 (menu softkey); or 29-99 (other button)
// Event = 0: release; 1: press; 2: longpress
void MakePushbuttonCAT(uint8_t ScanCode, uint8_t Event)
{
    uint32_t CatParam;
    CatParam = ScanCode * 10 + Event;
    MakeCATMessageNumeric(DESTTCPCATPORT, eZZZP, CatParam);
}



//
// makeproductversionCAT
// create a ZZZS Message
//
void MakeProductVersionCAT(uint8_t ProductID, uint8_t HWVersion, uint8_t SWVersion)
{
    uint32_t CatParam;
    CatParam = (ProductID * 100000) + (HWVersion*1000) + SWVersion;
    MakeCATMessageNumeric(DESTTCPCATPORT, eZZZS, CatParam);
}




