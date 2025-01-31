
/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// serialport.c:
//
// handle simple CAT access to serial port
// CAT messages are forwarded to CAT handler
// port is opened and read performed by creating a thread
//
//////////////////////////////////////////////////////////////

#include <termios.h>
#include <stdlib.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>

#include "serialport.h"
#include "cathandler.h"


//
// names of devices that thread has been opened for
//
char* DeviceNames[] =
{
  "G2V2 Panel",
  "G2V1 Panel Adapter",
  "AriesATU"
};



//
// open and set up a serial port for read/write access
//
int OpenSerialPort(char* DeviceName, unsigned int Baud)
{
    int Device;
    struct termios Ser;

    Device = open(DeviceName, O_RDWR);
    if(Device == -1)
    {
        printf("serial open failed on device %s\n", DeviceName);
    }
    else
    {
        memset(&Ser, 0, sizeof(Ser));
        Ser.c_iflag = IGNBRK | IGNPAR;
        Ser.c_cflag = CS8 | CREAD | HUPCL | CLOCAL;
        cfsetospeed(&Ser, Baud);
        cfsetispeed(&Ser, Baud);
        Ser.c_cc[VTIME] = 5;                // 0.5s timeout on read
        Ser.c_cc[VMIN] = 0;                 // read can return wioth no characters

        if (tcsetattr(Device, TCSANOW, &Ser) < 0) 
        {
            perror("tcsetattr()");
            return -1;
        }
        tcflush(Device, TCIFLUSH);
    }
    return Device;
}



//
// send a string to the serial port
//
void SendStringToSerial(int Device, char* Message)
{
    int Length;                                     // message length in charactera

    Length = strlen(Message);
    write(Device, Message, Length);
}




#define VESERINSIZE 120                 // large enough to hold a whole CAT message
//
// serial read thread
// the paramter passed is a pointer to a struct with the required settings
//
void* CATSerial(void *arg)
{
    char SerialInputBuffer[VESERINSIZE];
    char CATMessageBuffer[VESERINSIZE];
    int ReadCnt;
    int Cntr;
    int CATWritePtr = 0;
    char ch;                                    // individual read character
    int MatchPositionZZZS;
    int MatchPositionZZZP;

    TSerialThreadData *DeviceData;

    DeviceData = (TSerialThreadData *) arg;
    DeviceData -> DeviceHandle = OpenSerialPort(DeviceData -> PathName, DeviceData -> Baud);
    if(DeviceData -> DeviceHandle != -1)
    {
        printf("Setting up CAT Serial read handler thread for device %s\n", DeviceNames[(int)DeviceData->Device]);
        DeviceData -> IsOpen = true;
        DeviceData -> DeviceActive = true;
        sleep(1);                                   // allow serial to start (particularly for USB)

        if(DeviceData -> RequestID)
            write(DeviceData ->DeviceHandle, "ZZZS;", 5);

    //
    // now loop waiting for characters, then form them into CAT messages terminated by semicolon
    // read() will return after timoeut with no characters, so do check the count!
    //
        while(DeviceData -> DeviceActive)
        {
            ReadCnt = read(DeviceData -> DeviceHandle, &SerialInputBuffer, VESERINSIZE);
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
                    if (ch == ';')                                      // found end of a complete CAT message
                    {
                        CATMessageBuffer[CATWritePtr++] = 0;            // terminate the string
                        MatchPositionZZZS = (int)(strstr(CATMessageBuffer, "ZZZS") - CATMessageBuffer);
                        MatchPositionZZZP = (int)(strstr(CATMessageBuffer, "ZZZP") - CATMessageBuffer);
                        if((DeviceData -> Device == eG2V2Panel) ||(DeviceData -> Device == eG2V1PanelAdapter))
                        {
                        //
                        // if ZZZS or ZZZP, send to local handler; else send to SDR client app
                        //
                            if((MatchPositionZZZS == 0) || (MatchPositionZZZP == 0))
                                ParseCATCmd(CATMessageBuffer, DeviceData -> DeviceHandle);              // if ZZZS, process locally; else send to TCPIP CAT port
                            else
                                SendCATMessage(CATMessageBuffer);           // send unprocessed to SDR client app via TCP/IP
                        }
                        else
                        {
                        //
                        // for non front panel devices, process CAT commands locally
                        //
                            ParseCATCmd(CATMessageBuffer, DeviceData -> DeviceHandle);
                        }
                        CATWritePtr = 0;                                // reset for next CAT message
                    }
                }
            }
        }
        printf("Closing CAT Serial read handler thread for device %s\n", DeviceNames[(int)DeviceData->Device]);
        close(DeviceData -> DeviceHandle);
        DeviceData -> IsOpen = false;
    }
    return NULL;
}
