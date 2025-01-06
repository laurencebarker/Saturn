/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// AriesATU.c:
//
// interface the Aries ATU
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
#include "serialport.h"


bool AriesATUActive;                                // true if Aries is operating
bool AriesDetected;                                 // true if Aries detected from CAT message
TSerialThreadData AriesData;                        // data for G2V1 adapter read thread
pthread_t AriesSerialThread;                        // thread for serial read from Aries
pthread_t AriesTickThread;                          // thread with periodic tick


#define ARIESPATH "/dev/serial/by-id/usb-Arduino_LLC_Arduino_NANO_33_IoT_C707453A5050323339202020FF081E22-if00"                    // Aries ATU (note conflicts with G2V1 adapter)

// previously /dev/ttyACM0


//
// Aries periodic timestep
//
void AriesTick(void *arg)
{

    while(AriesATUActive)
    {
        usleep(100000);                                                  // 100ms period
    }

}


//
// function to initialise a connection to the  ATU; call if selected as a command line option
// create serial handler, and ask it to send a ZZZS. Then wait to see if a response provided.
// if a response from an Aries is received, set up periodic tick handler. 
//
void InitialiseAriesHandler(void)
{
    printf("checking for Aries ATU\n");

//
// launch serial handler for Aries
//
    strcpy(AriesData.PathName, ARIESPATH);
    AriesData.IsOpen = false;
    AriesData.RequestID = true;
    AriesData.Device = eAriesATU;

    if(pthread_create(&AriesSerialThread, NULL, CATSerial, (void *)&AriesData) < 0)
        perror("pthread_create Aries ATU thread");
    pthread_detach(AriesSerialThread);


    sleep(2);
//
// now see if anything came back from CAT handler
// disable devices if not used - this will cause it to close the file
// if setected, create periodic tick thread
//
    if(AriesDetected)
    {
        printf("Aries ATU Selected and Active\n");
        AriesATUActive = true;
        if(pthread_create(&AriesTickThread, NULL, AriesTick, NULL) < 0)
            perror("pthread_create Aries tick");
        pthread_detach(AriesTickThread);

    }
    else
    {
        AriesData.DeviceActive = false;
    }

}


//
// function to shutdown a connection to the  ATU; call if selected as a command line option
//
void ShutdownAriesHandler(void)
{
    AriesATUActive = false;                     // shut down tick thread
    AriesData.DeviceActive = false;             // shut down serial thread
    sleep(1);                                   // allow time for tick thread to close
}



//
// receive ZZZS state
// this has already been decoded by the CAT handler
//
void SetAriesZZZSState(uint8_t ProductID, uint8_t HWVersion, uint8_t SWID)
{
    if(ProductID == 2)
    {
        printf("found Aries ATU, product ID=%d", ProductID);
        printf("; H/W verson = %d", HWVersion);
        printf("; S/W verson = %d\n", SWID);
        AriesDetected = true;
    }
}



//
// receive a ZZZP message from Aries
//
void HandleAriesZZZPMessage(uint32_t Param)
{

}


//
// receive a ZZOX tune success message from Aries
//
void HandleAriesZZOXMessage(bool Param)
{

}

//
// receive a ZZOZ erase success message from Aries
//
void HandleAriesZZOZMessage(bool Param)
{

}


//
// see if serial device belongs to an Aries open serial port
// return true if this handle belongs to Aries ATU
//
bool IsAriesSerial(uint32_t Handle)
{
    bool Result = false;
    if((Handle==AriesData.DeviceHandle) && (AriesData.IsOpen == true))
        Result = true;
    return Result;
}


//
// set TX frequency from SDR App
// This is passed a delta phase word: convert to frequency
//
void SetAriesTXFrequency(uint32_t Newfreq)
{
    
}


//
// set Alex TX word from SDR App
//
void SetAriesAlexTXWord(uint16_t Word)
{

}

//
// set Alex RX word from SDR App
//
void SetAriesAlexRXWord(uint16_t Word)
{

}

bool GState = false;
bool RState = false;
//
// handle ATU button press on the G2V2 front panel
// State = 0: released; 1: pressed; 2: long pressed
//
void HandleATUButtonPress(uint8_t Event)
{
    printf("Aries ATU Button Press, Event=%d\n", Event);
    if(Event == 2)
    {
        RState = true;
        GState = false;
    }    
    else if(Event == 1)
        GState = true;
    else
    {
        GState = false;
        RState = false;
    }
    SetATULEDs(GState, RState);
}