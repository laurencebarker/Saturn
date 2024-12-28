


#include <termios.h>
#include <stdlib.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>

#include "serialport.h"


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