//
// test of write and to CODEC using DMA driver
// Laurence Barker December 2022
//
// ./codectest <frequency in Hz>
// so for 400 Hz test: command line ./codectest 400
//

#define _DEFAULT_SOURCE
#define _XOPEN_SOURCE 500

#include <assert.h>
#include <getopt.h>
#include <stdlib.h>
#include <time.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <stdio.h>
#include <errno.h>
#include <stdlib.h>
#include <limits.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <math.h>
#include <pthread.h>
#include <termios.h>
#include <sys/time.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <net/if.h>

#include "../common/saturntypes.h"
#include "../common/hwaccess.h"                     // access to PCIe read & write
#include "../common/saturnregisters.h"              // register I/O for Saturn
#include "../common/codecwrite.h"                   // codec register I/O for Saturn
#include "../common/version.h"                      // version I/O for Saturn



#define VALIGNMENT 4096


#define VSAMPLERATE 48000							// sample rate, Hz
#define VMEMBUFFERSIZE 2097152L						// memory buffer to reserve
#define AXIBaseAddress 0x40000L						// address of StreamRead/Writer IP
#define VDURATION 10								// seconds
#define VTOTALSAMPLES VSAMPLERATE * VDURATION
#define VDMATRANSFERSIZE 1024
#define VSAMPLEWORDSPERDMA 256
#define VDMAWORDSPERDMA 128							// 8 byte memory words
#define VDMATRANSFERS (VTOTALSAMPLES * 4) / VDMATRANSFERSIZE

#define VAMPLITUDE 0.1F


int DMAWritefile_fd = -1;											// DMA write file device
int DMAReadfile_fd = -1;											// DMA read file device


///
// not really needed!
//
void HandlerSetEERMode(void)
{

}


//
// create test data into memory buffer
// Samples is the number of samples to create
// data format is twos complement
// Freq is in Hz
void CreateTestData(char* MemPtr, uint32_t Samples, uint32_t Freq)
{
	uint32_t* Data;						// ptr to memory block to write data
	int16_t Word;						// a word of write data
	uint16_t UnsignedWord;
	uint32_t Cntr;						// memory counter
	double Sample;
	double Phase;
	double Ampl;
	uint32_t TwoWords;					// 32 bit L&R sample

	Phase = 2.0*M_PI*Freq / (double)VSAMPLERATE;		// 2 pi f t
	Ampl = 32767.0 * VAMPLITUDE;
	Data = (uint32_t *) MemPtr;
	for(Cntr=0; Cntr < Samples; Cntr++)
	{
//		Sample = 32768.0 + Ampl * sin(Phase * (double)Cntr);
		Sample = Ampl * sin(Phase * (double)Cntr);
		Word = (int16_t)Sample;
		UnsignedWord = (uint16_t)Word;
		TwoWords = (UnsignedWord << 16) | UnsignedWord;
		*Data++ = TwoWords;
	}
}



//
// DMA Write sample data t oCodec
// Length = number of bytes to transfer
void DMAWriteToCodec(char* MemPtr, uint32_t Length)
{
	uint32_t Depth = 0;
	bool FIFOOverflow;
	uint32_t DMACount;
	uint32_t  TotalDMACount;

	TotalDMACount = Length / VDMATRANSFERSIZE;
	printf("Starting Write DMAs; total = %d\n", TotalDMACount);

	for(DMACount = 0; DMACount < TotalDMACount; DMACount++)
	{
		Depth = ReadFIFOMonitorChannel(eSpkCodecDMA, &FIFOOverflow);        // read the FIFO free locations
//		printf("FIFO monitor read; depth = %d\n", Depth);
		while (Depth < VDMAWORDSPERDMA)       // loop till space available
		{
			usleep(1000);								                    // 1ms wait
			Depth = ReadFIFOMonitorChannel(eSpkCodecDMA, &FIFOOverflow);    // read the FIFO free locations
		}
		// DMA write next batch
		DMAWriteToFPGA(DMAWritefile_fd, MemPtr, VDMATRANSFERSIZE, AXIBaseAddress);
		MemPtr += VDMATRANSFERSIZE;
	}
	
}


//
// copy codec read data to codec write data
// read 16 bits; write 2 concatenated samples
// Length = number of MIC bytes to transfer
// need to read the bytes in, then write 2 copies to output buffer
//
void CopyMicToSpeaker(char* Read, char *Write, uint32_t Length)
{
	uint32_t *WritePtr;
	uint16_t *ReadPtr;
	uint16_t Sample;
	uint32_t TwoSamples;
	uint32_t Cntr;

	ReadPtr = (uint16_t *)Read;
	WritePtr = (uint32_t *)Write;

	for(Cntr=0; Cntr < Length/2; Cntr++)		// count 16 bit samples
	{
		Sample = *ReadPtr++;
		TwoSamples = (uint32_t)Sample;
		TwoSamples =((TwoSamples << 16) | TwoSamples);
		*WritePtr++ = TwoSamples;
	}
}



//
// DMA read sample data from Codec
// Length = number of bytes to transfer
// need to read the bytes in, then write 2 copies to output buffer
void DMAReadFromCodec(char* MemPtr, uint32_t Length)
{
	uint32_t Depth = 0;
	bool FIFOOverflow;
	uint32_t DMACount;
	uint32_t  TotalDMACount;

	TotalDMACount = Length / VDMATRANSFERSIZE;
	printf("Starting Read DMAs; total = %d\n", TotalDMACount);

	for(DMACount = 0; DMACount < TotalDMACount; DMACount++)
	{
		Depth = ReadFIFOMonitorChannel(eMicCodecDMA, &FIFOOverflow);        // read the FIFO free locations
		//printf("FIFO monitor read; depth = %d\n", Depth);
		while (Depth < VDMAWORDSPERDMA)       // loop till enough data available
		{
			usleep(1000);								                    // 1ms wait
			Depth = ReadFIFOMonitorChannel(eMicCodecDMA, &FIFOOverflow);    // read the FIFO free locations
		}
		// DMA read next batch
		// then read 16 bit samples, and write out 32 bit sample pairs
		//
		DMAReadFromFPGA(DMAReadfile_fd, MemPtr, VDMATRANSFERSIZE, AXIBaseAddress);
		MemPtr += VDMATRANSFERSIZE;
	}
}



//
// main program
//
int main(int argc, char *argv[])
{
  	char* WriteBuffer = NULL;											// data for DMA write
  	char* ReadBuffer = NULL;											// data for DMA read
	uint32_t BufferSize = VMEMBUFFERSIZE;
	uint32_t Frequency;
	uint32_t Length;


	if (argc != 2)
		printf("Usage: ./codectest <Freq in Hz>\n");
	else
		Frequency = (atoi(argv[1]));
	if(Frequency > 0)
	{
	//
	// initialise. Create memory buffers and open DMA file devices
	//
		OpenXDMADriver();
		PrintVersionInfo();
		CodecInitialise();
		SetByteSwapping(false);                                            // h/w to generate normalbyte order
		SetSpkrMute(false);

		posix_memalign((void **)&WriteBuffer, VALIGNMENT, BufferSize);
		if(!WriteBuffer)
		{
			printf("write buffer allocation failed\n");
			goto out;
		}

		posix_memalign((void **)&ReadBuffer, VALIGNMENT, BufferSize);
		if(!ReadBuffer)
		{
			printf("read buffer allocation failed\n");
			goto out;
		}

		DMAWritefile_fd = open("/dev/xdma0_h2c_0", O_RDWR);
		if(DMAWritefile_fd < 0)
		{
			printf("XDMA write device open failed\n");
			goto out;
		}

		DMAReadfile_fd = open("/dev/xdma0_c2h_0", O_RDWR);
		if(DMAReadfile_fd < 0)
		{
			printf("XDMA read device open failed\n");
			goto out;
		}

	//
	// we have devices and memory.
	// create test data, and display it
	//
		printf("resetting FIFO..\n");
		ResetDMAStreamFIFO(eSpkCodecDMA);
		ResetDMAStreamFIFO(eMicCodecDMA);
		printf("Creating test data\n");
		CreateTestData(WriteBuffer, VTOTALSAMPLES, Frequency);
	//
	// do DMA write
	//
		RegisterWrite(VADDRRFGPIOREG, 0x04);	// speaker on, mic on tip
		Length = VTOTALSAMPLES * 4;
		printf("Copying sample data to Codec via DMA\n");
		DMAWriteToCodec(WriteBuffer, Length);

		Length = VTOTALSAMPLES * 2;				// 2 bytes per mic sample
		printf("Reading mic data from Codec via DMA\n");
		ResetDMAStreamFIFO(eMicCodecDMA);
		DMAReadFromCodec(ReadBuffer, Length);
		DumpMemoryBuffer(ReadBuffer, 10240);

		CopyMicToSpeaker(ReadBuffer, WriteBuffer, Length);

		Length = VTOTALSAMPLES * 4;
		printf("Copying data to Codec via DMA\n");
		DMAWriteToCodec(WriteBuffer, Length);


	//
	// close down. Deallocate memory and close files
	//
out:
		close(DMAWritefile_fd);
		close(DMAReadfile_fd);
		free(WriteBuffer);
	}
}

