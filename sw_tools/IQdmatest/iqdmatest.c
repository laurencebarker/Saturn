//
// test of write and read I/Q data from FIFO
// using XDMA driver
// Laurence Barker December 2021
//  Plan A
//		record a block of 24 bit I&Q data from DDS in Litefury
//		dump data to I/Q
//		(established byte ordering)
// 
// Plan B
//		write CSV file & check data in Excel
//		(added FIFO reset function to FPGA so we can re-start)
// 
// Plan C
//		prototype for thread - open buffer, read many blocks and write CSV file
// 		(Jan 2022, current code)
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

#define VTRANSFERSIZE 4096										// size in bytes to DMA transfer
#define VMEMBUFFERSIZE 32768									// memory buffer to reserve
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


#define VCSVCOUNT 83					// 83 I/Q pairs similar to one USB frame
#define VPACKETSIZE VCSVCOUNT*6			// number of bytes needed for one CSV record
//
// write a packet of data to CSV; 
// sending <VCSVCOUNT> I/Q pairs. This is similar to a USB frame.
// parameters: 
//  fd		pointer to the already open file
//	Ptr		start location pointer into memory buffer
// 	Counter	pointer to integer I/Q value counter
//  returns the read pointer
unsigned char * CSVWrite(FILE* fd, unsigned char* Ptr, uint32_t* Counter)
{
	int Cntr;
	int32_t ISample, QSample;
	for(Cntr=0; Cntr < VCSVCOUNT; Cntr ++)
	{
		ISample = (*Ptr) <<24 | (*(Ptr+1)<<16) | (*(Ptr+2)<<8);
		Ptr += 3;
		QSample = (*Ptr) <<24 | (*(Ptr+1)<<16) | (*(Ptr+2)<<8);
		Ptr += 3;
		fprintf(fd, "%d, %d, %d\n", *Counter, ISample, QSample);
		*Counter += 1;
	}
	return Ptr;
}




#define VALIGNMENT 4096
#define VBASE 0x1000									// DMA start at 4K into buffer

//
// main program
//
int main(int argc, char *argv[])
{
	int DMAReadfile_fd = -1;											// DMA read file device
  	char* ReadBuffer = NULL;											// data for DMA write
	uint32_t BufferSize = 32768;

	uint32_t RegisterValue;
	uint32_t Depth = 0;
	FILE *fp;
	uint32_t SampleCounter = 0;

	uint32_t Head = 0;											// byte address of 1st free location
	uint32_t Read = 0;											// read point in buffer
	unsigned char* ReadPtr;									// pointer for reading out an I or Q sample
	unsigned char* HeadPtr;									// ptr to 1st free location
	unsigned char* BasePtr;									// ptr to DMA location
	uint32_t ResidueBytes;
//
// initialise. Create memory buffers and open DMA file devices
//
	posix_memalign((void **)&ReadBuffer, VALIGNMENT, BufferSize);
	if(!ReadBuffer)
	{
		printf("read buffer allocation failed\n");
		goto out;
	}
	ReadPtr = ReadBuffer + VBASE;							// offset 4096 bytes into buffer
	HeadPtr = ReadBuffer + VBASE;
	BasePtr = ReadBuffer + VBASE;

//
// try to open memory device, then DMA device
//
	if ((register_fd = open("/dev/xdma0_user", O_RDWR)) == -1)
    {
		printf("register R/W address space not available\n");
		goto out;
    }
    else
		printf("register access connected to /dev/xdma0_user\n");


	printf("Initialising XDMA read\n");
	DMAReadfile_fd = open("/dev/xdma0_c2h_0", O_RDONLY);

	if(DMAReadfile_fd < 0)
	{
		printf("XDMA read device open failed\n");
		goto out;
	}
//
// open CSV file
//
	fp = fopen("sine.csv", "w");

//
// now read the user access register (it should have a date code)
//
	RegisterValue = RegisterRead(0xB000);				// read the user access register
	printf("User register = %08x\n", RegisterValue);

//
// write 0 to GPIO to clear FIFO
//
	RegisterWrite(0xA000, 0);				// write to the GPIO register
	RegisterWrite(0xA000, 2);				// write to the GPIO register
	printf("GPIO Register written with value=0 then 2 to reset FIFO\n");
//
// read the FIFO depth register (it should be 0)
//
	RegisterValue = RegisterRead(0x9000);				// read the FIFO Depth register
	printf("FIFO Depth register = %08x (should be 0)\n", RegisterValue);
	Depth=0;

//
// write 3 to GPIO to enable FIFO writes
//
	RegisterWrite(0xA000, 3);				// write to the GPIO register
	printf("GPIO Register written with value=3, enabling writes\n");

//
// now read and dump data until we have at least 10000 samples
//
	while(SampleCounter < 10000)
	{
//
// here we write CSV values while there is enough data available; then do DMA to get more
//
		while((HeadPtr - ReadPtr)>VPACKETSIZE)
			ReadPtr = CSVWrite(fp, ReadPtr, &SampleCounter);
//
// now copy any residue to the start of the buffer (before the DMA point)
//
		ResidueBytes = HeadPtr-ReadPtr;
		printf("Residue = %d bytes\n",ResidueBytes);
		if(ResidueBytes != 0)					// if there is residue
		{
			memcpy(BasePtr-ResidueBytes, ReadPtr, ResidueBytes);
			ReadPtr = BasePtr-ResidueBytes;
		}
		else
			ReadPtr = BasePtr;

//
// now wait until there is data, then DMA it
//
		Depth = RegisterRead(0x9000);				// read the user access register
		printf("read: depth = %d\n", Depth);
		while(Depth < 512)			// 512 locations = 4K bytes
		{
			usleep(1000);								// 1ms wait
			Depth = RegisterRead(0x9000);				// read the user access register
			printf("read: depth = %d\n", Depth);
		}

		printf("DMA read %d bytes from destination to base\n", VTRANSFERSIZE);
		DMAReadFromFPGA(DMAReadfile_fd, BasePtr, VTRANSFERSIZE, AXIBaseAddress);
		HeadPtr = BasePtr + VTRANSFERSIZE;

	}  //while(SampleCounter < 10000)

	//
	// Disable write, Do a DMA read, then re-read depth register
	//
		RegisterWrite(0xA000, 2);				// write to the GPIO register
		printf("GPIO Register written with value=2\n");//
	//
	// read the FIFO depth register
	//
		RegisterValue = RegisterRead(0x9000);				// read the FIFO Depth register
		printf("FIFO Depth register at end after multiple DMA transfers = %d\n", RegisterValue);

	fclose(fp);



//
// close down. Deallocate memory and close files
//
out:
	close(DMAReadfile_fd);
	close(register_fd);

	free(ReadBuffer);
}

