//
// reads back all 8 SPI ADC values from AXI-lite bus
// Laurence Barker July 2022
//
// ./spiadcread
//

#define _DEFAULT_SOURCE
#define _XOPEN_SOURCE 500
#include <assert.h>
#include <fcntl.h>
#include <getopt.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>

#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include <unistd.h>

#define AXIBaseAddress 0x10000									// address of StreamRead/Writer IP

char* ChannelNames[] =
{
	"Fwd Voltage J15.7 ",
	"Rev Voltage J15.9 ",
	"J16 pin 12        ",
	"J16 pin 11        ",
	"Driver power      ",
	"13.8V supply      ",
	"Unused            ",
	"Unused            "
};

//
// mem read/write variables:
//
int register_fd;                             // device identifier

//
// 32 bit register write over the AXILite bus
//
void RegisterWrite(uint32_t Address, uint32_t Data)
{
	ssize_t nsent = pwrite(register_fd, &Data, sizeof(Data), (off_t)Address);
	if (nsent != sizeof(Data))
		printf("ERROR: Write: addr=0x%08X   error=%s\n", Address, strerror(errno));
}


uint32_t RegisterRead(uint32_t Address)
{
	uint32_t result = 0;

	ssize_t nread = pread(register_fd, &result, sizeof(result), (off_t)Address);
	if (nread != sizeof(result))
		printf("ERROR: register read: addr=0x%08X   error=%s\n", Address, strerror(errno));
	return result;
}



//
// main program
//
int main(void)
{
	uint32_t RegisterValue;
	uint32_t RegisterAddress;
	uint32_t Cntr;

	//
	// try to open memory device
	//
	if ((register_fd = open("/dev/xdma0_user", O_RDWR)) == -1)
	{
		printf("register R/W address space not available\n");
		goto out;
	}
	else
	{
		printf("register access connected to /dev/xdma0_user\n");

	}


	//
	// now read the user access register (it should have a date code)
	//
	RegisterValue = RegisterRead(0x4004);				// read the user access register
	printf("User register = %08x\n", RegisterValue);

	//
	// read registers
	//
	RegisterAddress = 0xA000;
	for (Cntr = 0; Cntr < 8; Cntr++)
	{
		RegisterValue = RegisterRead(RegisterAddress);
		RegisterAddress += 4;
		printf("channel %d: %s: data = %d\n", Cntr, ChannelNames[Cntr], RegisterValue);
	}


	//
	// close down. Deallocate memory and close files
	//
out:	close(register_fd);
}

