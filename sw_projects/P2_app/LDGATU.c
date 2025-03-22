/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// LDGATU.c:
//
// interface an LDG ATU, sending CAT command to request TUNE if required
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
#include "cathandler.h"


bool ATUControlled = false;
bool TuneRequestedState = false;                // true if tune power requested

//
// function to initialise a connection to the  ATU; call if selected as a command line option
//
void InitialiseLDGHandler(void)
{
    ATUControlled = true;
}


//
// function to request TUNE power
// paramter true to request tune power provision
//
void RequestATUTune(bool TuneRequested)
{
    if(ATUControlled)                // only do anything if ATU control has been requested
    {
        if(CATPortAssigned)
        {
            if(TuneRequested != TuneRequestedState)         // act on change only
            {
                TuneRequestedState = TuneRequested;
                MakeCATMessageBool(DESTTCPCATPORT, eZZTU, TuneRequested);
            }
        }
        else
            TuneRequestedState = false;                     // set not requested if connection lost
    }
}
