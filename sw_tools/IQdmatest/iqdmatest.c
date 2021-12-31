//
// test of write and read I/Q data from FIFO
// using XDMA driver
// Laurence Barker December 2021
//  Plan A
//		record a block of 24 bit I&Q data from DDS in Litefury
//		dump data to I/Q
// 
// Plan B
//		write CSV file & check data in Excel
// 
// Plan C
//		prototype for thread - open buffer, read many blocks and write CSV file
// 
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

#define VTRANSFERSIZE 4096											// size in bytes to transfer
#define VMEMBUFFERSIZE 32768										// memory buffer to reserve
#define AXIBaseAddress 0x18000									// address of StreamRead/Writer IP

//
// mem read/write variables:
//
	int register_fd;                             // device identifier



//
// dump a memory buffer to terminal in hex
// should be a multiple of 16 bytes long!
//
void DumpMemoryBuffer(char* MemPtr, uint32_t Length)
{
	unsigned char Byte;
	uint32_t ByteCntr;
  uint32_t RowCntr;

	for (RowCntr=0; RowCntr < Length/16; RowCntr++)
	{
		printf("%04x   ", RowCntr*16);
		for (ByteCntr = 0; ByteCntr < 16; ByteCntr++)
			printf("%02x ", *MemPtr++);
		printf("\n");
	}
}





//
// initiate a DMA from the FPGA with specified parameters
// returns 1 if success, else 0
// fd: file device (an open file)
// DestData: pointer to memory block to transfer
// Length: number of bytes to copy
// AXIAddr: offset address in the FPGA window 
//
int DMAReadFromFPGA(int fd, char*DestData, uint32_t Length, uint32_t AXIAddr)
{
	ssize_t rc;									// response code
	off_t OffsetAddr;

	OffsetAddr = AXIAddr;
	rc = lseek(fd, OffsetAddr, SEEK_SET);
	if (rc != OffsetAddr)
	{
		printf("seek off 0x%lx != 0x%lx.\n", rc, OffsetAddr);
		perror("seek file");
		return -EIO;
	}

	// write data to FPGA from memory buffer
	rc = read(fd, DestData, Length);
	if (rc < 0)
	{
		printf("read 0x%lx @ 0x%lx failed %ld.\n", Length, OffsetAddr, rc);
		perror("DMA read");
		return -EIO;
	}
	return 0;
}



uint32_t RegisterRead(uint32_t Address)
{
	uint32_t result = 0;

    ssize_t nread = pread(register_fd, &result, sizeof(result), (off_t) Address);
    if (nread != sizeof(result))
        printf("ERROR: register read: addr=0x%08X   error=%s\n",Address, strerror(errno));
	return result;
}


//
// 32 bit register write over the AXILite bus
//
void RegisterWrite(uint32_t Address, uint32_t Data)
{
    ssize_t nsent = pwrite(register_fd, &Data, sizeof(Data), (off_t) Address); 
    if (nsent != sizeof(Data))
        printf("ERROR: Write: addr=0x%08X   error=%s\n",Address, strerror(errno));
}








#define VALIGNMENT 4096



//
// main program
//
int main(int argc, char *argv[])
{
	int DMAReadfile_fd = -1;											// DMA read file device
  	char* ReadBuffer = NULL;											// data for DMA write
	uint32_t BufferSize = 32768;
	struct timespec ts_start, ts_read, ts_write;
	ssize_t rc;																		// return code from time functions
	double WriteTime, ReadTime;
	double WriteRate, ReadRate;
	uint32_t RegisterValue;
	uint32_t Depth;
	uint32_t Cntr;
	uint32_t ISample, QSample;
	uint32_t* Ptr;									// pointer for reading out an I or Q sample

//
// initialise. Create memory buffers and open DMA file devices
//
	posix_memalign((void **)&ReadBuffer, VALIGNMENT, BufferSize);
	if(!ReadBuffer)
	{
		printf("read buffer allocation failed\n");
		goto out;
	}

//
// try to open memory device, then DMA device
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


	printf("Initialising XDMA read\n");
	DMAReadfile_fd = open("/dev/xdma0_c2h_0", O_RDWR);

	if(DMAReadfile_fd < 0)
	{
		printf("XDMA read device open failed\n");
		goto out;
	}

//
// now read the user access register (it should have a date code)
//
	RegisterValue = RegisterRead(0xB000);				// read the user access register
	printf("User register = %08x\n", RegisterValue);

//
// read the FIFO depth register (it should be 0)
//
	RegisterValue = RegisterRead(0x9000);				// read the FIFO Depth register
	printf("FIFO Depth register = %08x (should be 0)\n", RegisterValue);

//
// write 1 to GPIO to enable FIFO writes
//
	RegisterWrite(0xA000, 1);				// write to the GPIO register
	printf("GPIO Register written with value=1\n");

//
// now read depth register until we get at least 4K bytes of samples
// (should take 13 milliseconds)
//
	Depth=0;
	Cntr=0;
	while(Depth < 0x200)
	{
		usleep(1000);								// 1ms wait
		Depth = RegisterRead(0x9000);				// read the user access register
		printf("iter %d: depth = %d\n", ++Cntr, Depth);
	}

//
// we now have at least 4K of data in the FIFO. Disable write, Do a DMA read, then re-read depth register
//
	RegisterWrite(0xA000, 0);				// write to the GPIO register
	printf("GPIO Register written with value=0\n");//

//
// do DMA read
//
	printf("DMA read %d bytes from destination\n", VTRANSFERSIZE);
	DMAReadFromFPGA(DMAReadfile_fd, ReadBuffer, VTRANSFERSIZE, AXIBaseAddress);
//
// read the FIFO depth register
//
	RegisterValue = RegisterRead(0x9000);				// read the FIFO Depth register
	printf("FIFO Depth register after DMA = %08x\n", RegisterValue);


//
// read one sample
//
	Ptr = (uint32_t *)ReadBuffer;
	ISample = (*Ptr) << 8;
	Ptr = (uint32_t *)(ReadBuffer+3);
	QSample = (*Ptr) << 8;
	printf("I sample= %08x; Q sample = %08x\n\n", ISample, QSample);

	DumpMemoryBuffer(ReadBuffer, VTRANSFERSIZE);


//
// close down. Deallocate memory and close files
//
out:
	close(DMAReadfile_fd);
	close(register_fd);

	free(ReadBuffer);
}

