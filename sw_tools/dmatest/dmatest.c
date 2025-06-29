//
// test of write and read DME using XDMA driver
// Laurence Barker July 2021
//
// ./dmatest <transfersize>
// so for 512 byte test: command line ./dmatest 512
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

//#define VTRANSFERSIZE 65536											// size in bytes to transfer
#define VMEMBUFFERSIZE 32768										// memory buffer to reserve
#define AXIBaseAddress 0x10000									// address of StreamRead/Writer IP

//
// mem read/write variables:
//
	int register_fd;                             // device identifier

//
// create test data into memory buffer
// size is the number of bytes to create - should be a multiple of 4
// 
void CreateTestData(char* MemPtr, uint32_t Size)
{
	uint16_t* Data;						// ptr to memory block to write data
	uint16_t Word;						// a word of write data

	uint32_t Cntr;						// memory counter

	Data = (uint16_t *) MemPtr;
	for(Cntr=0; Cntr < Size/2; Cntr++)
		*Data++ = Cntr;
}


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
// compare memory buffers to see if there are differences
// report success, or 1st error
// size is the number of bytes to compare - should be a multiple of 4
// return 0 if fail
//
int CompareMemoryBuffers (char* Block1, char* Block2, uint32_t Size)
{
	uint32_t* Ptr1;
	uint32_t* Ptr2;
	uint32_t Cntr;
	uint32_t Word1, Word2;
  int Result = 1;																// success or fail
	Ptr1 = (uint32_t *) Block1;
	Ptr2 = (uint32_t *) Block2;

	for(Cntr=0; Cntr < Size/4; Cntr++)
	{
		Word1 = *Ptr1++;
		Word2 = *Ptr2++;
		if (Word1 != Word2)
		{
			printf("Compare error. 1st nonmatching data at address %04x; data should be %04x; data found = %04x\n", Cntr*4, Word1, Word2);
			Result = 0;
			break;
		}
	}
	if (Result == 1)
		printf("Compare OK\n");
	return Result;
}



//
// initiate a DMA to the FPGA with specified parameters
// returns 1 if success, else 0
// fd: file device (an open file)
// SrcData: pointer to memory block to transfer
// Length: number of bytes to copy
// AXIAddr: offset address in the FPGA window 
//
int DMAWriteToFPGA(int fd, char*SrcData, uint32_t Length, uint32_t AXIAddr)
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
	rc = write(fd, SrcData, Length);
	if (rc < 0)
	{
		printf("write 0x%lx @ 0x%lx failed %ld.\n", Length, OffsetAddr, rc);
		perror("DMA write");
		return -EIO;
	}
	return 0;
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
	int DMAWritefile_fd = -1;											// DMA write file device
  	char* WriteBuffer = NULL;											// data for DMA write
  	char* ReadBuffer = NULL;											// data for DMA write
	uint32_t BufferSize = 32768;
	struct timespec ts_start, ts_read, ts_write;
	ssize_t rc;																		// return code from time functions
	double WriteTime, ReadTime;
	double WriteRate, ReadRate;
	uint32_t RegisterValue;
	uint32_t TransferSize = 0;

	if (argc != 2)
		printf("Usage: ./dmatest <transfersize>\n");
	else
		TransferSize = (atoi(argv[1]));
	if(TransferSize > 0)
	{
	//
	// initialise. Create memory buffers and open DMA file devices
	//
		posix_memalign((void **)&WriteBuffer, VALIGNMENT, BufferSize);
		posix_memalign((void **)&ReadBuffer, VALIGNMENT, BufferSize);
		if(!WriteBuffer)
		{
			printf("write buffer allocation failed\n");
			goto out;
		}
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


		printf("Initialising XDMA write\n");
		DMAReadfile_fd = open("/dev/xdma0_c2h_0", O_RDONLY);

		printf("Initialising XDMA read\n");
		DMAWritefile_fd = open("/dev/xdma0_h2c_0", O_WRONLY);
		if(DMAReadfile_fd < 0)
		{
			printf("XDMA read device open failed\n");
			goto out;
		}
		if(DMAWritefile_fd < 0)
		{
			printf("XDMA write device open failed\n");
			goto out;
		}

	//
	// we have devices and memory.
	// create test data, and display it
	//
		CreateTestData(WriteBuffer, TransferSize);

	//
	// do DMA write; get time taken into ts_write
	//
		printf("DMA write %d bytes to destination\n", TransferSize);
		rc = clock_gettime(CLOCK_MONOTONIC, &ts_start);
		DMAWriteToFPGA(DMAWritefile_fd, WriteBuffer, TransferSize, AXIBaseAddress);
		rc = clock_gettime(CLOCK_MONOTONIC, &ts_write);
		timespec_sub(&ts_write, &ts_start);

	//
	// now read the FIFO write and read depth FIFOs
	//
		RegisterValue = RegisterRead(0xD000);				// read the write depth count
		printf("FIFO write depth = %d\n", RegisterValue);
		RegisterValue = RegisterRead(0xD004);				// read the read depth count
		printf("FIFO read depth = %d\n", RegisterValue);

	//
	// do DMA read; get time taken into ts_read
	//
		printf("DMA read %d bytes from destination\n", TransferSize);
		rc = clock_gettime(CLOCK_MONOTONIC, &ts_start);
		DMAReadFromFPGA(DMAReadfile_fd, ReadBuffer, TransferSize, AXIBaseAddress);
		rc = clock_gettime(CLOCK_MONOTONIC, &ts_read);
		timespec_sub(&ts_read, &ts_start);
		
		CompareMemoryBuffers(WriteBuffer, ReadBuffer, TransferSize);
		DumpMemoryBuffer(ReadBuffer, TransferSize);

	//
	// now check timings
	//
		WriteTime = 1000.0*timespec2double(&ts_write);
		ReadTime = 1000.0*timespec2double(&ts_read);
		WriteRate = ((double)TransferSize) /(1.0E3*WriteTime);		// Mbyte/s
		ReadRate = ((double)TransferSize) /(1.0E3*ReadTime);		// Mbyte/s
		printf("Write time = %1.3fms; data rate = %3.1fMByte/s\n", WriteTime, WriteRate);
		printf("Read time = %1.3fms; data rate = %3.1fMByte/s\n", ReadTime, ReadRate);

	//
	// close down. Deallocate memory and close files
	//
out:
		close(DMAWritefile_fd);
		close(DMAReadfile_fd);
		close(register_fd);

		free(WriteBuffer);
		free(ReadBuffer);
	}
}

