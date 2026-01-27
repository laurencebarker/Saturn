/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// GanymedePAControl.c:
//
// interface the Ganymede PA controller
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
#include <syscall.h>

#include "../common/saturnregisters.h"
#include "../common/saturndrivers.h"
#include "../common/hwaccess.h"
#include "../common/debugaids.h"
#include "cathandler.h"
#include "serialport.h"
#include "GanymedePAControl.h"
#include "../common/version.h"


bool GanymedeActive;                                // true if Ganymede is operating
bool GanymedeDetected;                              // true if Ganymede detected from CAT message
bool GanymedeCATDetected = false;                   // true if Ganymede ZZZS ID message has been sent
ESoftwareID FirmwareID;

uint8_t GanymedeSWID;
uint8_t GanymedeHWVersion;
uint8_t GanymedeProductID;

uint32_t MostRecentAmplifierState;                      // reported amplifier state


TSerialThreadData GanymedeData;                     // data for Ganymede read thread
pthread_t GanymedeSerialThread;                        // thread for serial read from Ganymede
pthread_t GanymedeTickThread;                          // thread with periodic tick


#define GANYMEDEPATH "/dev/serial/by-path/g2-ganymede-9600"           // ganymede controller (note needs udev rule to map name)

#define P2APPVERSIONID 6
#define G2FIRMWAREVERSIONID 7

#define ID_GANYMEDE "c6e1f9a4-53b2-47d8-8c0e-2a7b5d14f963"





//
// Ganymede periodic timestep
// this runs as a thread,created at startup if Ganymede is detected.
// we may not need this!
//
void* GanymedeTick(__attribute__((unused)) void *arg)
{

    printf("opened Ganymede periodic tick thread, pid=%ld\n", syscall(SYS_gettid));
    while(GanymedeActive)
    {
        if(CATPortAssigned)                     // see if CAT has become available for the 1st time
        {
            if(GanymedeCATDetected == false)
            {
                GanymedeCATDetected = true;
                MakeProductVersionCAT(GanymedeProductID, GanymedeHWVersion, GanymedeSWID, DESTTCPCATPORT);
                MakeCATMessageString(DESTTCPCATPORT, eZZGA, ID_GANYMEDE);
                if(MostRecentAmplifierState != 0)
                    MakeCATMessageNumeric(DESTTCPCATPORT, eZZZA, MostRecentAmplifierState);        // forward message to TCP/IP port if amp is tripped

            }
        }
        else
            GanymedeCATDetected = false;

        usleep(20000);                                              // 20ms period
    }
    printf("Closing Ganymede tick thread\n");
    return NULL;
}


//
// function to initialise a connection to the PA controller; call at startup if selected as a command line option
// create serial handler, and ask it to send a ZZZS. Then wait to see if a response provided.
// if a response from an Ganymede is received, set up periodic tick handler. 
//
void InitialiseGanymedeHandler(void)
{
    printf("checking for Ganymede PA controller\n");

//
// launch serial handler for Ganymede
//
    strcpy(GanymedeData.PathName, GANYMEDEPATH);
    GanymedeData.IsOpen = false;
    GanymedeData.RequestID = true;
    GanymedeData.Device = eGanymedePAController;
    GanymedeData.Baud = B9600;

    if(pthread_create(&GanymedeSerialThread, NULL, CATSerial, (void *)&GanymedeData) < 0)
        perror("pthread_create Ganymede PA Controller thread");
    pthread_detach(GanymedeSerialThread);


    sleep(2);                               // ID request only goes out after 1s
//
// now see if anything came back from CAT handler
// disable devices if not used - this will cause it to close the file
// if detected, create periodic tick thread
// and send CAT commands for p2app, firmware versions
//
    if(GanymedeDetected)
    {
        printf("Ganymede PA Controller selected and Active\n");
        GanymedeActive = true;
        if(pthread_create(&GanymedeTickThread, NULL, GanymedeTick, NULL) < 0)
            perror("pthread_create Ganymede tick");
        pthread_detach(GanymedeTickThread);
        MakeProductVersionCAT(P2APPVERSIONID, 1, GetP2appVersion(), GanymedeData.DeviceHandle);
        MakeProductVersionCAT(G2FIRMWAREVERSIONID, GetPCBVersionNumber(), GetFirmwareVersion(&FirmwareID), GanymedeData.DeviceHandle);

    }
    else
        GanymedeData.DeviceActive = false;
}


//
// function to shutdown a connection to the PA Controller; call if selected as a command line option
//
void ShutdownGanymedeHandler(void)
{
    GanymedeActive = false;                     // shut down tick thread
    GanymedeData.DeviceActive = false;             // shut down serial thread
    sleep(1);                                   // allow time for tick thread to close
}



//
// receive ZZZS state
// this has already been decoded by the CAT handler
// store the ID values, so we can send out a message to TCP/IP when it connects
//
void SetGanymedeZZZSState(uint8_t ProductID, uint8_t HWVersion, uint8_t SWID)
{
    if(ProductID == 3)
    {
        printf("found Ganymede PA Controller, product ID=%d", ProductID);
        printf("; H/W verson = %d", HWVersion);
        printf("; S/W verson = %d\n", SWID);
        GanymedeDetected = true;
        GanymedeProductID = ProductID;
        GanymedeHWVersion = HWVersion;
        GanymedeSWID = SWID;

    }
}



//
// see if serial device belongs to a Ganymede open serial port
// return true if this handle belongs to Ganymede PA Controller
//
bool IsGanymedeSerial(int Handle)
{
    bool Result = false;
    if((Handle==GanymedeData.DeviceHandle) && (GanymedeData.IsOpen == true))
        Result = true;
    return Result;
}




//
// receive a ZZZA message from Ganymede
// SourceDevice identifies where the message came from
// 
void HandleGanymedeZZZAMessage(uint32_t Param, int SourceDevice)
{
    if(SourceDevice != DESTTCPCATPORT)                  // source was Ganymede itself
    {
        MostRecentAmplifierState = Param; 
        MakeCATMessageNumeric(DESTTCPCATPORT, eZZZA, Param);        // forward message to TCP/IP port
        printf("Incoming ZZZA from Ganymede, data=%d\n",Param);
    }
    else
    {
        MakeCATMessageNumeric(GanymedeData.DeviceHandle, eZZZA, Param);        // forward message to Ganymede
        printf("Incoming ZZZA from TCP/IP port, data=%d\n",Param);
    }
}


