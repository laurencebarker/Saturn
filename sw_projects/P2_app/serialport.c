
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
// handle simple access to serial port
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
int OpenSerialPort(char* DeviceName)
{
    int Device;
    struct termios Ser;

    Device = open(DeviceName, O_RDWR);
    if(Device == 0)
    {
        printf("serial open failed on device %s\n", DeviceName);
    }

	memset(&Ser, 0, sizeof(Ser));
	Ser.c_iflag = IGNBRK | IGNPAR;
	Ser.c_cflag = CS8 | CREAD | HUPCL | CLOCAL;
	cfsetospeed(&Ser, B9600);
	cfsetispeed(&Ser, B9600);
    Ser.c_cc[VTIME] = 0;                // no timeout on read
    Ser.c_cc[VMIN] = 1;                 // read will return just one character

	if (tcsetattr(Device, TCSANOW, &Ser) < 0) 
    {
		perror("tcsetattr()");
		return -1;
	}
	tcflush(Device, TCIFLUSH);

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


//
// function ot test whether any characters are present in the serial port
// return true if there are.
//
bool AreCharactersPresent(int Device)
{
    bool Result = false;
    int Chars;

    ioctl(Device, FIONREAD, &Chars);             // see if any characters returned
    if(Chars != 0)                                  // if we get none, panel not present; close device
        Result = true;
    return Result;
}


#define VESERINSIZE 120                 // large enough to hold a whole CAT message
//
// serial read thread
// the paramter passed is a pointer to a struct with the required settings
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
    TSerialThreadData *DeviceData;

    DeviceData = (TSerialThreadData *) arg;
    printf("CAT Serial read handler thread established for device %s\n", DeviceNames[(int)DeviceData->Device]);
//
// now loop waiting for characters, then form them into CAT messages terminated by semicolon
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
                if (ch == ';')
                {
                    CATMessageBuffer[CATWritePtr++] = 0;            // terminate the string
                    MatchPosition = (int)(strstr(CATMessageBuffer, "ZZZS") - CATMessageBuffer);
                    if(MatchPosition == 0)
                        ParseCATCmd(CATMessageBuffer, DeviceData -> DeviceHandle);              // if ZZZS, process locally; else send to TCPIP CAT port
                    else
                        SendCATMessage(CATMessageBuffer);           // send unprocessed to SDR client app via TCP/IP
                    CATWritePtr = 0;                                // reset for next CAT message
                }
            }
        }
    }
}
