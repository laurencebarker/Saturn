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
unsigned int CurrentTXAntenna = 0;                  // 0 if not known.
unsigned int CurrentRXAntenna = 0;                  // 0 if not known.
uint32_t CurrentFrequency = 0;                      // 10KHz units. 0 if not known
bool EnabledForAntenna[4] = {false, false, false, false};  // enabled state for each possible TX antenna 0 entry is "unknown antenna"
bool GreenLEDState = false;                                    // green LED state
bool RedLEDState = false;                                    // red LED state


extern bool IsTXMode;                               // true if in TX


#define ARIESPATH "/dev/serial/by-id/aries-atu-115200"                    // Aries ATU (note needs udev rule to map name)



//
// Aries periodic timestep
// this runs as a thread,created at startup if Aries is detected.
//
void AriesTick(void *arg)
{
    bool PreviousTXMode = false;                                    // for detecting TX state change
    bool PreviousSDRActive = false;                                 // for detecting SDR active state change

    printf("opened Aries periodic tick thread\n");
    while(AriesATUActive)
    {
        //
        // look for a change in SDR active
        //
        if(SDRActive != PreviousSDRActive)                          // state change
        {
            PreviousSDRActive = SDRActive;                          // state change recognised
            if(SDRActive == false)
            {
                CurrentTXAntenna = 0;
                CurrentRXAntenna = 0;
                CurrentFrequency = 0;
            }
        }

        //
        // look for a change in TX state
        // if we enter TX, send out a TUNE request message to find if this is a TUNE or not. 
        //
        if(IsTXMode != PreviousTXMode)                              // state change
        {
            PreviousTXMode = IsTXMode;                          // state change recognised
            if(IsTXMode)
                MakeCATMessageNoParam(DESTTCPCATPORT, eZZTU);
        }
        usleep(20000);                                              // 20ms period
    }
    printf("Closing Aries tick thread\n");

}


//
// function to initialise a connection to the  ATU; call at startup if selected as a command line option
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
    AriesData.Baud = B9600;

    if(pthread_create(&AriesSerialThread, NULL, CATSerial, (void *)&AriesData) < 0)
        perror("pthread_create Aries ATU thread");
    pthread_detach(AriesSerialThread);


    sleep(2);                               // ID request only goes out after 1s
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
        AriesData.DeviceActive = false;
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
// response from a ZZTU; tune state request
//
void SetAriesTuneState(bool Param)
{
    if(Param)
        printf("Aries detected TUNE state\n");
    else
        printf("Aries detected normal TX state\n");
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
// set ATU Enabled or Disabled
// send message to ATU, and set LED appropriately
//
void SetAriesEnabledState(bool IsEnabled)
{
//  MakeCATMessageBool(AriesData.DeviceHandle, eZZOV, IsEnabled);            // set enabled state

}

//
// set TX frequency from SDR App
// This is passed a delta phase word: convert to frequency first
//
void SetAriesTXFrequency(uint32_t NewFreq)
{
    double Frequency;
    uint32_t Freq_Hz;
    uint32_t Freq_10KHz;
    Frequency = (double)(NewFreq * 0.0286102 + 0.5);            // convert to Hz, rounded
    Freq_Hz = (uint32_t)Frequency;
    Freq_10KHz = Frequency / 10000;
    if(Freq_10KHz != CurrentFrequency)
    {
        CurrentFrequency = Freq_10KHz;
        printf("Aries get Freq in 10KHz units = %d\n", Freq_10KHz);
    }
}


//
// set Alex TX word from SDR App, bytes 1428, 29 from V4.3 protocol.
// we should require that the newer Thetis is used for this.
// ANT1 is bit 8; ANT3 is bit 10 
//
void SetAriesAlexTXWord(uint16_t Word)
{
    unsigned int Antenna = 0;
    if(Word & 0x0100)
        Antenna = 1;
    else if(Word & 0x0200)
        Antenna = 2;
    else if(Word & 0x0400)
        Antenna = 3;
    if((CurrentTXAntenna != Antenna) && (Antenna != 0))
    {
        CurrentTXAntenna = Antenna;
        if(AriesATUActive)
        {
            printf("Aries detected TX Ant=%d\n", Antenna);
            if(EnabledForAntenna[Antenna])
            {
//                MakeCATMessageNumeric(AriesData.DeviceHandle, eZZOC, Antenna);      // set antenna
                SetAriesEnabledState(true);            // set enabled state
            }
            else
            {
                SetAriesEnabledState(false);            // set enabled state
//                MakeCATMessageNumeric(AriesData.DeviceHandle, eZZOC, Antenna);      // set antenna
            }
        }
    }
}

//
// set Alex RX word from SDR App. bytes 1430, 31 from V4.3 protocol.
// we should require that the newer Thetis is used for this.
// ANT1 is bit 8; ANT3 is bit 10 
//
void SetAriesAlexRXWord(uint16_t Word)
{
    unsigned int Antenna = 0;
    if(Word & 0x0100)
        Antenna = 1;
    else if(Word & 0x0200)
        Antenna = 2;
    else if(Word & 0x0400)
        Antenna = 3;
    if(CurrentRXAntenna != Antenna)
    {
        CurrentRXAntenna = Antenna;
        if(AriesATUActive)
        {   
//            MakeCATMessageNumeric(AriesData.DeviceHandle, eZZOA, Antenna);
            printf("Aries detected RX Ant=%d\n", Antenna);
        }
    }
}

//
// handle ATU button press on the G2V2 front panel
// State = 0: released; 1: pressed; 2: long pressed
//
void HandleATUButtonPress(uint8_t Event)
{
    printf("Aries ATU Button Press, Event=%d\n", Event);
    if(Event == 2)
    {
        RedLEDState = true;
        GreenLEDState = false;
    }    
    else if(Event == 1)
        GreenLEDState = true;
    else
    {
        GreenLEDState = false;
        RedLEDState = false;
    }
    SetATULEDs(GreenLEDState, RedLEDState);
}