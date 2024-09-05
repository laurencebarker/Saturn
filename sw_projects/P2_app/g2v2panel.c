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
#include <termios.h>

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
int SerialDev;                                      // serial device


#define VKEEPALIVECOUNT 150                         // 15s period between keepalive requests (based on 100ms tick)




//
// send a CAT message to the panel
//
void SendCATtoPanel(char* Message)
{
    int Length;                                     // message length in charactera
    int Cntr;

    Length = strlen(Message);
    write(SerialDev, Message, Length);
}





//
// setup serial port
//
void SetupG2V2PanelSerial(void)
{
    int Retval;
    bool Error;                                                     // i2c error flag
    int bits;
    struct termios Ser;

//
// setup serial; then send CAT message to read product ID and version register
//
    SerialDev = open(G2ARDUINOPATH, O_RDWR);
    if(SerialDev == 0)
    {
        printf("serial open failed\n");
    }


// this removed code is needed for USB serial, but not for native serial port
//	if (ioctl(SerialDev, TIOCMGET, &bits) < 0) 
//    {
//		close(SerialDev);
//		perror("ioctl(TCIOMGET)");
//		return -1;
//	}

//	bits &= ~(TIOCM_DTR | TIOCM_RTS);
//	if (ioctl(SerialDev, TIOCMSET, &bits) < 0) {
//		close(SerialDev);
//		perror("ioctl(TIOCMSET)");
//		return -1;
//	}
//	sleep(1);
//	tcflush(SerialDev, TCIFLUSH);
//	bits &= TIOCM_DTR;
//	if (ioctl(SerialDev, TIOCMSET, &bits) < 0) 
//    {
//		close(SerialDev);
//		perror("ioctl(TIOCMSET)");
//		return -1;
//	}

	memset(&Ser, 0, sizeof(Ser));
	Ser.c_iflag = IGNBRK | IGNPAR;
	Ser.c_cflag = CS8 | CREAD | HUPCL | CLOCAL;
	cfsetospeed(&Ser, B9600);
	cfsetispeed(&Ser, B9600);
    Ser.c_cc[VTIME] = 0;                // no timeout on read
    Ser.c_cc[VMIN] = 1;                 // read will return just one character

	if (tcsetattr(SerialDev, TCSANOW, &Ser) < 0) 
    {
		perror("tcsetattr()");
		return -1;
	}
	tcflush(SerialDev, TCIFLUSH);
}



//
// function to check if panel is present. 
// file can be left open if "yes".
//
bool CheckG2V2PanelPresent(void)
{
    int Chars;                                      // returned character count
//  return (access(G2ARDUINOPATH, F_OK)==0);        // this wirks for USB, but not for the always-present on board serial
    SetupG2V2PanelSerial();
    SendCATtoPanel("ZZZS;");
    sleep(1);                                       // if any chars come back, there is a panel attached
    ioctl(SerialDev, FIONREAD, &Chars);             // see if any characters returned

    if(Chars == 0)                                  // if we get none, panel not present; close device
        close(SerialDev);
    return(Chars != 0);
}


#define VESERINSIZE 120                 // large enough to hold a whole CAT message
//
// serial read thread
//
void G2V2PanelSerial(void *arg)
{
    char SerialInputBuffer[VESERINSIZE];
    char CATMessageBuffer[VESERINSIZE];
    int ReadCnt;
    int Cntr;
    int CATWritePtr = 0;
    char ch;                                    // individual read character
    int MatchPosition;

    printf("G2 panel Serial read handler thread established\n");
//
// now loop waiting for characters, then form them into CAT messages terminated by semicolon
//
    while(G2V2PanelActive)
    {
        ReadCnt = read(SerialDev, &SerialInputBuffer, VESERINSIZE);
        if (ReadCnt > 0)
        {
//
// we have input data available, so read it one char at a time and write to buffer
// if we find a terminating semicolon, process the command
// if we get a control character, abandon the line so far and start again
//
            for(Cntr=0; Cntr < ReadCnt; Cntr++)
            {
                ch=SerialInputBuffer[Cntr];
                CATMessageBuffer[CATWritePtr++] = ch;
                if (ch == ';')
                {
                    CATMessageBuffer[CATWritePtr++] = 0;            // terminate the string
                    MatchPosition = (int)(strstr(CATMessageBuffer, "ZZZS") - CATMessageBuffer);
                    if(MatchPosition == 0)
                        ParseCATCmd(CATMessageBuffer);              // if ZZZS, process locally; else send to TCPIP CAT port
                    else
                        SendCATMessage(CATMessageBuffer);
                    CATWritePtr = 0;                                // reset for next CAT message
                }
            }
        }
    }
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
                    MakeCATMessageNoParam(eZZXV);
                    break;

                case 1:
                    MakeCATMessageNoParam(eZZUT);
                    break;

                case 2:
                    MakeCATMessageNoParam(eZZYR);
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
            MakeCATMessageNoParam(eZZXV);
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
            char IndicatorMessage[10];

            for(Cntr=0; Cntr < VNUMG2V2INDICATORS; Cntr++)
            {
                if((NewLEDStates & Mask) != (GLEDState & Mask))
                {
                    NewState = (NewLEDStates & Mask) >> Cntr;
                    Param = ((Cntr +1)* 10) + NewState;
                    MakeCATMessageNumeric_Local(eZZZI, Param, IndicatorMessage);
                    SendCATtoPanel(IndicatorMessage);

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
// initialise serial; and create threads for tick andserial read
//
void InitialiseG2V2PanelHandler(void)
{
    G2V2PanelControlled = true;
    printf("Initialising G2V2 panel handler\n");
    G2V2PanelActive = true;

    if(pthread_create(&G2V2PanelTickThread, NULL, G2V2PanelTick, NULL) < 0)
        perror("pthread_create G2 panel tick");
    pthread_detach(G2V2PanelTickThread);

    if(pthread_create(&G2V2PanelSerialThread, NULL, G2V2PanelSerial, NULL) < 0)
        perror("pthread_create G2 panel tick");
    pthread_detach(G2V2PanelSerialThread);

}


//
// function to shutdown a connection to the G2 front panel; call if selected as a command line option
//
void ShutdownG2V2PanelHandler(void)
{
    G2V2PanelActive = false;
    close(SerialDev);
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
    char IndicatorMessage[10];
    GZZZIReceived = true;
    MakeCATMessageNumeric_Local(eZZZI, Param, IndicatorMessage);
    SendCATtoPanel(IndicatorMessage);

}
