/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// g2panel.c:
//
// interface G2V2 front panel using asynchronous serial
//
//////////////////////////////////////////////////////////////

#include "g2v2panel.h"
#include "threaddata.h"
#include <stdbool.h>
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
#include "serialport.h"

#include "../common/saturnregisters.h"
#include "../common/saturndrivers.h"
#include "../common/hwaccess.h"
#include "../common/debugaids.h"
#include "cathandler.h"

#include <linux/i2c-dev.h>
#include "i2cdriver.h"
#include "gpiod.h"
#include "andromedacatmessages.h"


bool G2V2PanelControlled = false;
bool G2V2PanelActive = false;                       // true while panel active and threads should run
bool G2V2CATDetected = false;                       // true if panel ID message has been sent
bool GZZZIReceived = false;                         // true if a ZZZI message received (so halt polling)

extern int i2c_fd;                                  // file reference
char* gpio_dev = NULL;
pthread_t G2V2PanelTickThread;                      // thread with periodic tick
pthread_t G2V2PanelSerialThread;                    // thread wfor serial read from panel
uint8_t G2V2PanelSWID;
uint8_t G2V2PanelHWVersion;
uint8_t G2V2PanelProductID;
uint32_t VKeepAliveCnt;                             // count of ticks for keepalive
uint8_t CATPollCntr;                                // determines which message to poll for
bool G2ToneState;                                   // true if 2 tone test in progress
bool GVFOBSelected;                                 // true if VFO B selected
uint32_t GCombinedVFOState;                         // reported VFO state bits
uint16_t GLEDState;                                 // LED state settings
TSerialThreadData G2V2Data;                         // data for G2V2 read thread

#define VKEEPALIVECOUNT 150                         // 15s period between keepalive requests (based on 100ms tick)




//
// send a CAT message to the panel
//
void SendCATtoPanel(char* Message)
{
    SendStringToSerial(G2V2Data.DeviceHandle, Message);
}




//
// function to check if panel is present. This is called before panel initialise.
// file can be left open if "yes".
//
bool CheckG2V2PanelPresent(void)
{
    int SerialDev;                                      // serial device
    bool CharsPresent;                                      // returned character count

//  return (access(G2ARDUINOPATH, F_OK)==0);        // this wirks for USB, but not for the always-present on board serial
    printf("checking for G2V2\n");

    SerialDev = OpenSerialPort(G2ARDUINOPATH);
    G2V2Data.DeviceHandle = SerialDev;
    G2V2Data.DeviceActive = true;
    G2V2Data.Device = eG2V2Panel;
    SendCATtoPanel("ZZZS;");
    sleep(1);      
    CharsPresent = AreCharactersPresent(SerialDev);                                 // if any chars come back, there is a panel attached

    if(!CharsPresent)                                  // if we get none, panel not present; close device
        close(SerialDev);
    else
    {
        printf("found characters from G2V2; spinning up thread\n");
        if(pthread_create(&G2V2PanelSerialThread, NULL, G2V2PanelSerial, (void *)&G2V2Data) < 0)
            perror("pthread_create G2 panel tick");
        pthread_detach(G2V2PanelSerialThread);
    }
    return(CharsPresent);
}







#define VNUMG2V2INDICATORS 9
//
// periodic timestep
//
void G2V2PanelTick(void *arg)
{
    uint32_t NewLEDStates = 0;

    while(G2V2PanelActive)
    {
        if(CATPortAssigned)                     // see if CAT has become available for the 1st time
        {
            if(G2V2CATDetected == false)
            {
                G2V2CATDetected = true;
                MakeProductVersionCAT(G2V2PanelProductID, G2V2PanelHWVersion, G2V2PanelSWID);
            }
        }
        else
            G2V2CATDetected = false;
//
// poll CAT, if we haven't been sent an indicator message
//
        if(GZZZIReceived == false)
            switch(CATPollCntr++)
            {
                case 0:
                    MakeCATMessageNoParam(DESTTCPCATPORT, eZZXV);
                    break;

                case 1:
                    MakeCATMessageNoParam(DESTTCPCATPORT, eZZUT);
                    break;

                case 2:
                    MakeCATMessageNoParam(DESTTCPCATPORT, eZZYR);
                    break;

                default:
                    CATPollCntr = 0;
                    break;
            }
//
// check keepalive
// keep this in case we can ditch the polling at some point
//
        if(VKeepAliveCnt++ > VKEEPALIVECOUNT)
        {
            VKeepAliveCnt = 0;
            MakeCATMessageNoParam(DESTTCPCATPORT, eZZXV);
        }
//
// Set LEDs from values reported by CAT messages
// store into NewLEDStates; then set to I2C create ZZZI if different from what we had before
// ATU tune LEDs are internal to P2app, not Thetis
//
        if(GZZZIReceived == false)
        {
            NewLEDStates = 0;
            if((GCombinedVFOState & (1<<6)) != 0)
                NewLEDStates |= 1;                          // MOX bit
            if((GCombinedVFOState & (1<<7)) != 0)
                NewLEDStates |= (1 << 1);                   // TUNE bit
            if(G2ToneState)
                NewLEDStates |= (1 << 2);                   // 2 tone bit
            if((GCombinedVFOState & (1<<8)) != 0)
                NewLEDStates |= (1 << 6);                   // XIT bit
            if((GCombinedVFOState & (1<<0)) != 0)
                NewLEDStates |= (1 << 5);                   // RIT bit
            if(!GVFOBSelected)
                NewLEDStates |= (1 << 7);                   // led lit if VFO A selected

            if((((GCombinedVFOState & (1<<2)) != 0) && GVFOBSelected) ||
            (((GCombinedVFOState & (1<<1)) != 0) && !GVFOBSelected))
                NewLEDStates |= (1 << 8);                   // VFO Lock bit

//
// now loop through to find differences
// do bitwise compares; if differences found, senz a ZZZI message
            int Cntr;
            int Mask = 1;
            int NewState;
            int Param;

            for(Cntr=0; Cntr < VNUMG2V2INDICATORS; Cntr++)
            {
                if((NewLEDStates & Mask) != (GLEDState & Mask))
                {
                    NewState = (NewLEDStates & Mask) >> Cntr;
                    Param = ((Cntr +1)* 10) + NewState;
                    MakeCATMessageNumeric(G2V2Data.DeviceHandle, eZZZI, Param);

                }
                Mask = Mask << 1;                               // bitmask for next bit
            }
            GLEDState = NewLEDStates;
        }

        usleep(100000);                                                  // 100ms period

    }

}



//
// function to initialise a connection to the G2 V2 front panel; call if selected as a command line option
// this is called *after* the G2V2 panel has been discovered.
// create threads for tick
//
void InitialiseG2V2PanelHandler(void)
{
    G2V2PanelControlled = true;
    printf("Initialising G2V2 panel handler\n");
    G2V2PanelActive = true;

    if(pthread_create(&G2V2PanelTickThread, NULL, G2V2PanelTick, NULL) < 0)
        perror("pthread_create G2 panel tick");
    pthread_detach(G2V2PanelTickThread);
}


//
// function to shutdown a connection to the G2 front panel; call if selected as a command line option
//
void ShutdownG2V2PanelHandler(void)
{
    G2V2PanelActive = false;
    close(G2V2Data.DeviceHandle);
}


//
// receive ZZUT state
//
void SetG2V2ZZUTState(bool NewState)
{
    G2ToneState = NewState;
}


//
// receive ZZYR state
//
void SetG2V2ZZYRState(bool NewState)
{
    GVFOBSelected = NewState;
}



//
// receive ZZXV state
//
void SetG2V2ZZXVState(uint32_t NewState)
{
    GCombinedVFOState = NewState;
}



//
// receive ZZZS state
//
void SetG2V2ZZZSState(uint32_t Param)
{
    G2V2PanelProductID = Param / 100000;
    Param = Param % 100000;
    G2V2PanelHWVersion = Param / 1000;
    G2V2PanelSWID= Param % 1000;
    printf("found panel product ID=%d", G2V2PanelProductID);
    printf("; H/W verson = %d", G2V2PanelHWVersion);
    printf("; S/W verson = %d\n", G2V2PanelSWID);
}



//
// receive ZZZI state
// set that it has been seen, and make an outgoing message for the panel
//
void SetG2V2ZZZIState(uint32_t Param)
{
    GZZZIReceived = true;
    MakeCATMessageNumeric(G2V2Data.DeviceHandle, eZZZI, Param);

}


