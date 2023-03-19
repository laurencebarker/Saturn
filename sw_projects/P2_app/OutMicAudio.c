/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// OutMicAudio.c:
//
// handle "outgoing microphone audio" message
//
//////////////////////////////////////////////////////////////

#include "threaddata.h"
#include <stdint.h>
#include "../common/saturntypes.h"
#include "OutMicAudio.h"
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <stddef.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include "../common/saturnregisters.h"
#include "../common/saturndrivers.h"
#include "../common/hwaccess.h"


#define VMICSAMPLESPERFRAME 64
#define VDMABUFFERSIZE 32768						// memory buffer to reserve
#define VALIGNMENT 4096                             // buffer alignment
#define VBASE 0x1000                                // offset into I/Q buffer for DMA to start
#define VDMATRANSFERSIZE 128                        // read 1 message at a time



// this runs as its own thread to send outgoing data
// thread initiated after a "Start" command
// will be instructed to stop & exit by main loop setting enable_thread to 0
// this code signals thread terminated by setting active_thread = 0
// for now this code aims to send out packets until it is just ahead of the I/Q packets
//
void *OutgoingMicSamples(void *arg)
{
//
// variables for outgoing UDP frame
//
    struct iovec iovecinst;                                 // instance of iovec
    struct msghdr datagram;
    uint8_t UDPBuffer[VMICPACKETSIZE];                      // DDC frame buffer
    uint32_t SequenceCounter = 0;                           // UDP sequence count

    struct ThreadSocketData* ThreadData;            // socket etc data for this thread
    struct sockaddr_in DestAddr;                    // destination address for outgoing data
    bool InitError = false;
    int Error;

//
// variables for DMA buffer 
//
    uint8_t* MicReadBuffer = NULL;							// data for DMA read from DDC
    uint32_t MicBufferSize = VDMABUFFERSIZE;
    unsigned char* MicReadPtr;								// pointer for reading out a mic sample
    unsigned char* MicHeadPtr;								// ptr to 1st free location in mic memory
    unsigned char* MicBasePtr;								// ptr to DMA location in mic memory
    uint32_t Depth = 0;
    int DMAReadfile_fd = -1;									// DMA read file device
    uint32_t RegisterValue;
    bool FIFOOverflow;


//
// initialise. Get parameters for thread; 
// then create memory buffers and open DMA file devices
//
    ThreadData = (struct ThreadSocketData *)arg;
    ThreadData->Active = true;
    printf("spinning up outgoing mic thread with port %d\n", ThreadData->Portid);

//
// setup DMA buffer
//
    posix_memalign((void**)&MicReadBuffer, VALIGNMENT, MicBufferSize);
    if (!MicReadBuffer)
    {
        printf("mic read buffer allocation failed\n");
        InitError = true;
    }
    MicReadPtr = MicReadBuffer + VBASE;							// offset 4096 bytes into buffer
    MicHeadPtr = MicReadBuffer + VBASE;
    MicBasePtr = MicReadBuffer + VBASE;
    memset(MicReadBuffer, 0, MicBufferSize);


  //
  // open DMA device driver
  //
    DMAReadfile_fd = open(VMICDMADEVICE, O_RDWR);
    if (DMAReadfile_fd < 0)
    {
        printf("XDMA read device open failed for mic data\n");
        InitError = true;
    }

  //
  // now initialise Saturn hardware.
  // ***This os debug code at the moment. ***
  // clear FIFO
  // then read depth
  //
    SetupFIFOMonitorChannel(eMicCodecDMA, false);
    ResetDMAStreamFIFO(eMicCodecDMA);
    RegisterValue = ReadFIFOMonitorChannel(eMicCodecDMA, &FIFOOverflow);				// read the FIFO Depth register
    printf("mic FIFO Depth register = %08x (should be 0)\n", RegisterValue);
    Depth = 0;


  //
  // planned strategy: just DMA mic data when available; don't copy and DMA a larger amount.
  // if sufficient FIFO data available: DMA that data and transfer it out. 
  // if it turns out to be too inefficient, we'll have to try larger DMA.
  //
    while (!InitError)
    {
        while(!(SDRActive))
        {
            if(ThreadData->Cmdid & VBITCHANGEPORT)
            {
                printf("Mic data request change port\n");
                close(ThreadData->Socketid);                      // close old socket, open new one
                MakeSocket(ThreadData, 0);                        // this binds to the new port.
                ThreadData->Cmdid &= ~VBITCHANGEPORT;             // clear command bit
            }
            usleep(100);
        }
    //
    // if we get here, run has been initiated
    // initialise outgoing data packet
    //
        SequenceCounter = 0;
        memcpy(&DestAddr, &reply_addr, sizeof(struct sockaddr_in));           // create local copy of PC destination address
        memset(&iovecinst, 0, sizeof(struct iovec));
        memset(&datagram, 0, sizeof(datagram));
        iovecinst.iov_base = UDPBuffer;
        iovecinst.iov_len = VMICPACKETSIZE;
        datagram.msg_iov = &iovecinst;
        datagram.msg_iovlen = 1;
        datagram.msg_name = &DestAddr;                              // MAC addr & port to send to
        datagram.msg_namelen = sizeof(DestAddr);

        while(SDRActive && !InitError)                              // main loop
        {
            //
            // now wait until there is data, then DMA it
            //
            Depth = ReadFIFOMonitorChannel(eMicCodecDMA, &FIFOOverflow);			// read the FIFO Depth register. 4 mic words per 64 bit word.
            while (Depth < (VMICSAMPLESPERFRAME/4))			        // 16 locations = 64 samples
            {
                usleep(1000);								        // 1ms wait
                Depth = ReadFIFOMonitorChannel(eMicCodecDMA, &FIFOOverflow);				// read the FIFO Depth register
            }

            DMAReadFromFPGA(DMAReadfile_fd, MicBasePtr, VDMATRANSFERSIZE, VADDRMICSTREAMREAD);

            // create the packet into UDPBuffer
            *(uint32_t*)UDPBuffer = htonl(SequenceCounter++);        // add sequence count
            memcpy(UDPBuffer+4, MicBasePtr, VDMATRANSFERSIZE);       // copy in mic samples
            Error = sendmsg(ThreadData -> Socketid, &datagram, 0);
            if(Error == -1)
            {
                perror("sendmsg, Mic Audio");
                InitError=true;
            }
        }
    }
//
// tidy shutdown of the thread
//
    if(InitError)                                           // if error, flag it to main program
      ThreadError = true;

    printf("shutting down outgoing mic data thread\n");
    close(ThreadData->Socketid); 
    ThreadData->Active = false;                   // signal closed
    return NULL;
}
