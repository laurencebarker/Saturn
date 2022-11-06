/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// OutDDCIQ.c:
//
// handle "outgoing DDC I/Q data" message
//
//////////////////////////////////////////////////////////////

#include "threaddata.h"
#include <stdint.h>
#include "../common/saturntypes.h"
#include "OutMicAudio.h"
#include <errno.h>
#include <stdlib.h>
#include <stddef.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include "../common/saturnregisters.h"
#include "../common/saturndrivers.h"



// temp variable for getting mic sample rate correct
extern uint32_t TransferredIQSamples;



//
// global holding the current step of C&C data. Each new USB frame updates this.
//
#define VDMABUFFERSIZE 32768									      // memory buffer to reserve
#define VALIGNMENT 4096                             // buffer alignment
#define VBASE 0x1000									              // DMA start at 4K into buffer
#define VBASE 0x1000                                // offset into I/Q buffer for DMA to start
#define VDMATRANSFERSIZE 4096                       // read 4K at a time  *** DEBUG amount***

#define VDDCPACKETSIZE 1444
#define VIQSAMPLESPERFRAME 238                      // total I/Q samples in one DDC packet
#define VIQBYTESPERFRAME 6*VIQSAMPLESPERFRAME       // total bytes in one outgoing frame



//
// this runs as its own thread to send outgoing data
// thread initiated after a "Start" command
// will be instructed to stop & exit by main loop setting enable_thread to 0
// this code signals thread terminated by setting active_thread = 0
//
void *OutgoingDDCIQ(void *arg)
{
//
// memory buffers
//
  uint8_t* IQReadBuffer = NULL;											// data for DMA read from DDC
  uint32_t IQBufferSize = VDMABUFFERSIZE;
  bool InitError = false;                         // becomes true if we get an initialisation error
  unsigned char* IQReadPtr;								        // pointer for reading out an I or Q sample
  unsigned char* IQHeadPtr;								        // ptr to 1st free location in I/Q memory
  unsigned char* IQBasePtr;								        // ptr to DMA location in I/Q memory
  uint32_t ResidueBytes;
  uint32_t Depth = 0;
  int DMAReadfile_fd = -1;											  // DMA read file device
  uint32_t RegisterValue;
  bool FIFOOverflow;


  struct ThreadSocketData *ThreadData;            // socket etc data for this thread
  struct sockaddr_in DestAddr;                    // destination address for outgoing data


//
// variables for outgoing UDP frame
//
  struct iovec iovecinst;                                 // instance of iovec
  struct msghdr datagram;
  uint8_t UDPBuffer[VDDCPACKETSIZE];                      // DDC frame buffer
  uint32_t SequenceCounter = 0;                           // UDP sequence count

//
// initialise. Create memory buffers and open DMA file devices
//
  ThreadData = (struct ThreadSocketData *)arg;
  ThreadData->Active = true;
  printf("spinning up outgoing I/Q thread with port %d\n", ThreadData->Portid);

	posix_memalign((void **)&IQReadBuffer, VALIGNMENT, IQBufferSize);
	if(!IQReadBuffer)
	{
		printf("I/Q read buffer allocation failed\n");
		InitError = true;
	}
	IQReadPtr = IQReadBuffer + VBASE;							// offset 4096 bytes into buffer
	IQHeadPtr = IQReadBuffer + VBASE;
	IQBasePtr = IQReadBuffer + VBASE;
  memset(IQReadBuffer, 0, IQBufferSize);


//
// open DMA device driver
//    this will probably have to move, as there won't be enough of them!
//
	DMAReadfile_fd = open(VDDCDMADEVICE, O_RDWR);
	if(DMAReadfile_fd < 0)
	{
		printf("XDMA read device open failed for DDC data\n");
		InitError = true;
	}

//
// now initialise Saturn hardware.
// ***This os debug code at the moment. ***
// clear FIFO
// then read depth
//
    SetupFIFOMonitorChannel(eRXDDCDMA, false);
    ResetDMAStreamFIFO(eRXDDCDMA);
    RegisterValue = ReadFIFOMonitorChannel(eRXDDCDMA, &FIFOOverflow);				// read the FIFO Depth register
	printf("FIFO Depth register = %08x (should be 0)\n", RegisterValue);
	Depth=0;
    TransferredIQSamples = 0;


//
// thread loop. runs continuously until commanded by main loop to exit
// for now: add 1 RX data + mic data at 48KHz sample rate. Mic data is constant zero.
// while there is enough I/Q data, make outgoing packets;
// when not enough data, read more.
//
  while(!InitError)
  {
    while(!SDRActive)
    {
      if(ThreadData->Cmdid & VBITCHANGEPORT)
      {
        close(ThreadData->Socketid);                      // close old socket, open new one
        MakeSocket(ThreadData, 0);                        // this binds to the new port.
        ThreadData->Cmdid &= ~VBITCHANGEPORT;             // clear command bit
      }
      usleep(100);
    }
    printf("starting outgoing data\n");
    //
    // initialise outgoing DDC packet
    //
    SequenceCounter = 0;
    memcpy(&DestAddr, &reply_addr, sizeof(struct sockaddr_in));           // local copy of PC destination address
    memset(&iovecinst, 0, sizeof(struct iovec));
    memset(&datagram, 0, sizeof(datagram));
    iovecinst.iov_base = UDPBuffer;
    iovecinst.iov_len = VDDCPACKETSIZE;
    datagram.msg_iov = &iovecinst;
    datagram.msg_iovlen = 1;
    datagram.msg_name = &DestAddr;                   // MAC addr & port to send to
    datagram.msg_namelen = sizeof(DestAddr);

  //
  // enable Saturn DDC to transfer data
  //
    SetDDCInterleaved(0, false);
    SetRXDDCEnabled(true);
    printf("enabled DDC\n");
    while(!InitError && SDRActive)
    {
    
      //
      // while there is enough I/Q data in ARM memory, make DDC Packets
      //
      while((IQHeadPtr - IQReadPtr)>VIQBYTESPERFRAME)
      {
        *(uint32_t *)UDPBuffer = htonl(SequenceCounter++);        // add sequence count
        memset(UDPBuffer+4, 0,8);                                 // clear the timestamp data
        *(uint16_t *)(UDPBuffer+12) = htons(24);                         // bits per sample
        *(uint32_t *)(UDPBuffer+14) = htons(VIQSAMPLESPERFRAME);         // I/Q samples for ths frame
        //
        // now add I/Q data & send outgoing packet
        //
        memcpy(UDPBuffer + 16, IQReadPtr, VIQBYTESPERFRAME);
        IQReadPtr += VIQBYTESPERFRAME;

        int Error;
        Error = sendmsg(ThreadData -> Socketid, &datagram, 0);
        TransferredIQSamples += VIQSAMPLESPERFRAME;

        if(Error == -1)
        {
          printf("Send Error, errno=%d\n",errno);
          printf("socket id = %d\n", ThreadData -> Socketid);
          InitError=true;
        }
      }
      //
      // now bring in more data via DMA
      // first copy any residue to the start of the buffer (before the DMA point)
  //
      ResidueBytes = IQHeadPtr- IQReadPtr;
  //		printf("Residue = %d bytes\n",ResidueBytes);
      if(ResidueBytes != 0)					// if there is residue
      {
        memcpy(IQBasePtr-ResidueBytes, IQReadPtr, ResidueBytes);
        IQReadPtr = IQBasePtr-ResidueBytes;
      }
      else
        IQReadPtr = IQBasePtr;
  //
  // now wait until there is data, then DMA it
  //
      Depth = ReadFIFOMonitorChannel(0, 0, &FIFOOverflow);				// read the FIFO Depth register
  //		printf("read: depth = %d\n", Depth);
      while(Depth < 512)			// 512 locations = 4K bytes
      {
        usleep(1000);								// 1ms wait
        Depth = ReadFIFOMonitorChannel(0, 0, &FIFOOverflow);				// read the FIFO Depth register
    //			printf("read: depth = %d\n", Depth);
      }

  //		printf("DMA read %d bytes from destination to base\n", VDMATRANSFERSIZE);
      DMAReadFromFPGA(DMAReadfile_fd, IQBasePtr, VDMATRANSFERSIZE, VADDRDDCSTREAMREAD);
      IQHeadPtr = IQBasePtr + VDMATRANSFERSIZE;
    }     // end of while(!InitError) loop
  }

//
// tidy shutdown of the thread
//
  printf("shutting down DDC outgoing thread\n");
  close(ThreadData->Socketid); 
  ThreadData->Active = false;                   // signal closed
  free(IQReadBuffer);
  return NULL;
}


//
// interface calls to get commands from PC settings
// sample rate, DDC enabled and interleaved are all signalled through the socket 
// data structure
//
// the meanings are:
// enabled - the DDC sends data in its own right
// interleaved - can be set for "even" DDCs; the next higher odd DDC also has its data routed
// through here. That DDC is NOT enabled. 
//


//
// HandlerCheckDDCSettings()
// called when DDC settings have been changed. Check which DDCs are enabled, and sample rate.
//
void HandlerCheckDDCSettings(void)
{

}


//
// HandlerSetDDCEnabled(unsigned int DDC, bool Enabled)
// set whether a DDC is enabled
// SHOULD BE OBSOLETE NOW ********************************************************
void HandlerSetDDCEnabled(unsigned int DDC, bool Enabled)
{
  if(!Enabled)
    SocketData[VPORTDDCIQ0 + DDC].Cmdid &= ~VBITDDCENABLE;
  else
  {
    SocketData[VPORTDDCIQ0 + DDC].Cmdid |= VBITDDCENABLE;
    printf("DDC %d enabled\n", DDC);
  }
  //SetDDCEnabled(DDC, Enabled);                          // placeholder - move tohandler
}


//
// HandlerSetDDCInterleaved(unsigned int DDC, bool Interleaved)
// set whether a DDC is interleaved
// this is called for odd DDCs, and if interleaved synchs to next lower number
// eg DDC3 can synch to DDC2
//
void HandlerSetDDCInterleaved(unsigned int DDC, bool Interleaved)
{
  if(!Interleaved)
    SocketData[VPORTDDCIQ0 + DDC].Cmdid &= ~VBITINTERLEAVE;
  else
  {
    SocketData[VPORTDDCIQ0 + DDC].Cmdid |= VBITINTERLEAVE;
    printf("DDC %d interleave enabled\n", DDC);
  }
  //SetDDCInterleaved(DDC, Interleaved);      // placeholder
}


//
// HandlerSetP2SampleRate(unsigned int DDC, unsigned int SampleRate)
// sets the sample rate for a single DDC (used in protocol 2)
// allowed rates are 48KHz to 1536KHz.
//
void HandlerSetP2SampleRate(unsigned int DDC, unsigned int SampleRate)
{
  SocketData[VPORTDDCIQ0 + DDC].DDCSampleRate = SampleRate;
  //SetP2SampleRate(DDC, SampleRate);         // do set this here!
}
