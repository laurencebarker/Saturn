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
// interface G2V2 front panel using I2C
//
//////////////////////////////////////////////////////////////

#include "g2v2panel.h"
#include "threaddata.h"
#include <stdbool.h>
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

#include <linux/i2c-dev.h>
#include "i2cdriver.h"
#include "gpiod.h"
#include "andromedacatmessages.h"


bool G2V2PanelControlled = false;
bool G2V2PanelActive = false;                       // true while panel active and threads should run
bool G2V2CATDetected = false;                       // true if panel ID message has been sent

extern int i2c_fd;                                  // file reference
char* gpio_dev = NULL;
struct gpiod_line *intline;
pthread_t G2V2PanelTickThread;                      // thread with periodic tick
pthread_t G2V2PanelInterruptThread;                 // thread with periodic tick
uint8_t G2V2PanelSWID;
uint8_t G2V2PanelHWVersion = 1;
uint8_t G2V2PanelProductID;
uint32_t VKeepAliveCnt;                             // count of ticks for keepalive
uint8_t CATPollCntr;                                // determines which message to poll for
static struct gpiod_chip *chip = NULL;
bool G2ToneState;                                   // true if 2 tone test in progress
bool GVFOBSelected;                                 // true if VFO B selected
uint32_t GCombinedVFOState;                         // reported VFO state bits
uint16_t GLEDState;                                 // LED state settings



#define VKEEPALIVECOUNT 150                         // 15s period between keepalive requests (based on 100ms tick)
#define VNOEVENT 0
#define VVFOSTEP 1
#define VENCODERSTEP 2
#define VPBPRESS 3
#define VPBLONGRESS 4
#define VPBRELEASE 5


//
// set GPIO interrupt line to required state
//
void SetupG2V2PanelGPIO(void)
{
    chip = NULL;

    //
    // Open GPIO device. Try devices for RPi4 and RPi5
    //
    if (chip == NULL)
    {
        gpio_dev = "/dev/gpiochip4";      // works on RPI5
        chip = gpiod_chip_open(gpio_dev);
    }

    if (chip == NULL)
    {
        gpio_dev = "/dev/gpiochip0";     // works on RPI4
        chip = gpiod_chip_open(gpio_dev);
    }

    //
    // If no connection, give up
    //
    if (chip == NULL)
        printf("%s: open gpio chip failed\n", __FUNCTION__);
    else
    {
        printf("%s: G2V2 panel GPIO device=%s\n", __FUNCTION__, gpio_dev);

        intline = gpiod_chip_get_line(chip, 4);
        if(!intline)
            perror("gpiod_chip_get_line");

//
// setup interrupt line as an input, with falling edge events
//    
        gpiod_line_request_falling_edge_events(intline, "interrupt");
    }
}




//
// 
//
void SetupG2V2PanelI2C(void)
{
int Retval;
bool Error;                                                     // i2c error flag
//
// read product ID and version register
//
    Retval = i2c_read_word_data(0x0C, &Error);                  // read ID register (also clears interrupt)
    if(!Error)
    {
        G2V2PanelProductID = (Retval >> 8) &0xFF;
        printf("found panel product ID=%d", G2V2PanelProductID);
        G2V2PanelSWID = Retval & 0xFF;
        printf("; S/W verson = %d\n", G2V2PanelSWID);
    }
}



//
// lookup from a G2V2 scan code to a Thetis scan code
//
uint8_t ScanCode2Thetis[] =
{
    0, 1, 3, 11, 49, 50, 48, 47, 
    45, 44, 43, 42, 9, 5, 31, 32, 
    30, 34, 35, 33, 36, 37, 38, 39, 
    40, 41, 0, 30, 31, 32, 33, 34, 
    35, 36, 37, 38, 39, 40, 41, 0, 
    0, 7
};



//
// Get Thetis Scan Code
// lookup scan code, and indicate whether a SHIFT is needed
//
uint8_t GetThetisScanCode(uint8_t V2Code, bool* Shifted)
{
    uint8_t NewScanCode;

    if((V2Code >= 27) && (V2Code <= 38))
        *Shifted = true;
    else
        *Shifted = false;                               // assume no shift
    NewScanCode = ScanCode2Thetis[V2Code];
    return NewScanCode;
}

#define VTHETISSHIFTSCANCODE 29



//
// interrupt thread
//
void G2V2PanelInterrupt(__attribute__((unused)) void *arg)
{
    uint16_t Retval;
    uint8_t EventCount;
    uint8_t EventID;
    uint8_t EventData;
    int8_t Steps;
    bool Error;
    struct timespec ts = {1, 0};                                    // timeout time = 1s
    struct gpiod_line_event intevent;
    uint8_t Encoder;
    bool ThetisPBShift;
    uint8_t ThetisScanCode;

    printf("G2 panel Interrupt Handler thread established\n");
//
// now loop waiting for interrupt, then reading the i2c Event register
// need to read all i2c data, until it reports no more events
//
    while(G2V2PanelActive)
    {
        Retval = gpiod_line_event_wait(intline, &ts);                   // wait for interrupt from Arduino
        if(Retval > 0)                                                  // if event occurred ie not timeout
        {
            Retval = gpiod_line_event_read(intline, &intevent);         // UNDOCUMENTED: read event to cancel it
            //
            // the interrupt line has reached zero. Read and process one i2c event
            // if there is more than one event present, the interrupt line will stay low
            //
            while(1)
            {
                Retval = i2c_read_word_data(0x0B, &Error);                  // read Arduino i2c event register
                if(!Error)
                {
                    printf("data=%04x; ", Retval);
                    EventID = (Retval >> 8) & 0x0F;
                    EventCount = (Retval >> 12) & 0x0F;
                    EventData = Retval & 0x7F;

                    switch(EventID)
                    {
                        case VNOEVENT:
                            break;
                                
                        case VVFOSTEP:
                            Steps = (int8_t)(EventData);
                            Steps |= ((Steps & 0x40) << 1);         // sign extend
                            MakeVFOEncoderCAT(Steps);
                            break;

                        case VENCODERSTEP:
                            Steps = (int8_t)(EventData & 0x7);
                            if (Steps >= 4)
                                Steps = -(8-Steps);
                            Encoder = ((EventData>>3) + 1);
                            MakeEncoderCAT(Steps, Encoder);
                            break;

                        case VPBPRESS:
//                            ThetisScanCode = GetThetisScanCode(EventData, &ThetisPBShift);
//                            if(ThetisPBShift)
//                            {
//                                MakePushbuttonCAT(VTHETISSHIFTSCANCODE, 1);
//                                MakePushbuttonCAT(VTHETISSHIFTSCANCODE, 0);
//                            }
//                            MakePushbuttonCAT(ThetisScanCode, 1);
                            MakePushbuttonCAT(EventData, 1);
                            printf("Pushbutton press, scan code = %d; ", EventData);
                            break;

                        case VPBLONGRESS:
//                            ThetisScanCode = GetThetisScanCode(EventData, &ThetisPBShift);
//                            MakePushbuttonCAT(ThetisScanCode, 2);
                            MakePushbuttonCAT(EventData, 2);
                            printf("Pushbutton longpress, scan code = %d; ", EventData);
                            break;

                        case VPBRELEASE:
//                            ThetisScanCode = GetThetisScanCode(EventData, &ThetisPBShift);
//                            MakePushbuttonCAT(ThetisScanCode, 0);
                            MakePushbuttonCAT(EventData, 0);
                            printf("Pushbutton release, scan code = %d; ", EventData);
                            break;

                        default:
                            printf("spurious event code = %d; ", EventID);
                            break;

                    }
                    printf(" Remaining Events Count = %d\n", EventCount);
                    if(EventCount <= 1)
                        break;
                }
                usleep(1000);                                                   // small 1ms delay between i2c reads
            }
        }
    }
}






//
// periodic timestep
//
void G2V2PanelTick(__attribute__((unused)) void *arg)
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
// poll CAT
//
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
// store into NewLEDStates; then set to I2C if different from what we had before
// ATU tune LEDs are internal to P2app, not Thetis
//
        NewLEDStates = 0;
        if((GCombinedVFOState & (1<<6)) != 0)
            NewLEDStates |= 1;                          // MOX bit
        if((GCombinedVFOState & (1<<7)) != 0)
            NewLEDStates |= (1 << 1);                   // TUNE bit
        if(G2ToneState)
            NewLEDStates |= (1 << 2);                   // 2 tone bit
        if((GCombinedVFOState & (1<<8)) != 0)
            NewLEDStates |= (1 << 5);                   // XIT bit
        if((GCombinedVFOState & (1<<0)) != 0)
            NewLEDStates |= (1 << 6);                   // RIT bit
        if(GVFOBSelected)
            NewLEDStates |= (1 << 7);                   // VFO B bit

        if((((GCombinedVFOState & (1<<2)) != 0) && GVFOBSelected) ||
        (((GCombinedVFOState & (1<<1)) != 0) && !GVFOBSelected))
            NewLEDStates |= (1 << 8);                   // VFO Lock bit


        if(NewLEDStates != GLEDState)
        {
            GLEDState = NewLEDStates;
            i2c_write_word_data(0x0A, NewLEDStates);
        }

        usleep(100000);                                                  // 100ms period

    }

}



//
// function to initialise a connection to the G2 V2 front panel; call if selected as a command line option
// initialise i2c and GPIO; and create threads for tick and interrupt
//
void InitialiseG2V2PanelHandler(void)
{
    G2V2PanelControlled = true;
    printf("Initialising G2V2 panel handler\n");
    SetupG2V2PanelGPIO();
    SetupG2V2PanelI2C();
    G2V2PanelActive = true;

    if(pthread_create(&G2V2PanelTickThread, NULL, G2V2PanelTick, NULL) < 0)
        perror("pthread_create G2 panel tick");
    pthread_detach(G2V2PanelTickThread);

    if(pthread_create(&G2V2PanelInterruptThread, NULL, G2V2PanelInterrupt, NULL) < 0)
        perror("pthread_create G2 panel tick");
    pthread_detach(G2V2PanelInterruptThread);
}


//
// function to shutdown a connection to the G2 front panel; call if selected as a command line option
//
void ShutdownG2V2PanelHandler(void)
{
    if (chip != NULL)
    {
        G2V2PanelActive = false;
        sleep(2);                                       // wait 2s to allow threads to close
        gpiod_line_release(intline);
        gpiod_chip_close(chip);
    }
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
