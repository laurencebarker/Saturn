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
#define AXIBaseAddress 0x10000									// address of StreamRead/Writer IP

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

/* Subtract timespec t2 from t1
 *
 * Both t1 and t2 must already be normalized
 * i.e. 0 <= nsec < 1000000000
 */
static int timespec_check(struct timespec *t)
{
	if ((t->tv_nsec < 0) || (t->tv_nsec >= 1000000000))
		return -1;
	return 0;

}

void timespec_sub(struct timespec *t1, struct timespec *t2)
{
	if (timespec_check(t1) < 0) {
		fprintf(stderr, "invalid time #1: %lld.%.9ld.\n",
			(long long)t1->tv_sec, t1->tv_nsec);
		return;
	}
	if (timespec_check(t2) < 0) {
		fprintf(stderr, "invalid time #2: %lld.%.9ld.\n",
			(long long)t2->tv_sec, t2->tv_nsec);
		return;
	}
	t1->tv_sec -= t2->tv_sec;
	t1->tv_nsec -= t2->tv_nsec;
	if (t1->tv_nsec >= 1000000000) {
		t1->tv_sec++;
		t1->tv_nsec -= 1000000000;
	} else if (t1->tv_nsec < 0) {
		t1->tv_sec--;
		t1->tv_nsec += 1000000000;
	}
}


double timespec2double(struct timespec *t1)
{
	double Result;

	Result = t1->tv_sec+((double)(t1->tv_nsec)/1.0E9);
	return Result;
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
	RegisterValue = RegisterRead(0xB000);				// read the user access register
	printf("User register = %08x\n", RegisterValue);


	printf("Initialising XDMA read\n");
	DMAReadfile_fd = open("/dev/xdma0_c2h_0", O_RDWR);

	if(DMAReadfile_fd < 0)
	{
		printf("XDMA read device open failed\n");
		goto out;
	}



//
// do DMA read; get time taken into ts_read
//
	printf("DMA read %d bytes from destination\n", VTRANSFERSIZE);
	DMAReadFromFPGA(DMAReadfile_fd, ReadBuffer, VTRANSFERSIZE, AXIBaseAddress);
	DumpMemoryBuffer(ReadBuffer, VTRANSFERSIZE);


//
// close down. Deallocate memory and close files
//
out:
	close(DMAReadfile_fd);
	close(register_fd);

	free(ReadBuffer);
}

