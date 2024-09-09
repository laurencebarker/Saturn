/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// InSpkrAudio.c:
//
// handle "incoming speaker audio" message
//
//////////////////////////////////////////////////////////////

#include "threaddata.h"
#include <stdint.h>
#include "InSpkrAudio.h"
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


#define VSPKSAMPLESPERFRAME 64                      // samples per UDP frame
#define VMEMWORDSPERFRAME 32                        // 8 byte writes per UDP msg
#define VSPKSAMPLESPERMEMWORD 2                     // 2 samples (each 4 bytes) per 8 byte word
#define VDMABUFFERSIZE 32768						            // memory buffer to reserve
#define VALIGNMENT 4096                             // buffer alignment
#define VBASE 0x1000								                // DMA start at 4K into buffer
#define VDMATRANSFERSIZE 256                        // write 1 message at a time
#define VSTARTUPDELAY 100                           // 100 messages (~100ms) before reporting under or overflows


//
// listener thread for incoming DDC (speaker) audio packets
// planned strategy: just DMA spkr data when available; don't copy and DMA a larger amount.
// if sufficient FIFO data available: DMA that data and transfer it out. 
// if it turns out to be too inefficient, we'll have to try larger DMA.
//
void *IncomingSpkrAudio(void *arg)                      // listener thread
{
    struct ThreadSocketData *ThreadData;                  // socket etc data for this thread
    struct sockaddr_in addr_from;                         // holds MAC address of source of incoming messages
    uint8_t UDPInBuffer[VSPEAKERAUDIOSIZE];               // incoming buffer
    struct iovec iovecinst;                               // iovcnt buffer - 1 for each outgoing buffer
    struct msghdr datagram;                               // multiple incoming message header
    ssize_t size;                                         // UDP datagram length

//
// variables for DMA buffer 
//
    uint8_t* SpkWriteBuffer = NULL;							// data for DMA to write to spkr
    uint32_t SpkBufferSize = VDMABUFFERSIZE;
    bool InitError = false;                                 // becomes true if we get an initialisation error
    unsigned char* SpkReadPtr;								              // pointer for reading out a spkr sample
    unsigned char* SpkHeadPtr;								              // ptr to 1st free location in spk memory
    unsigned char* SpkBasePtr;								              // ptr to DMA location in spk memory
    uint32_t Depth = 0;
    int DMAWritefile_fd = -1;								                // DMA read file device
    bool FIFOOverflow, FIFOUnderflow, FIFOOverThreshold;
    uint32_t RegVal = 0;
    uint32_t Current;                                       // current occupied locations in FIFO
    unsigned int StartupCount;                              // used to delay reporting of under & overflows
    bool PrevSDRActive = false;                             // used to detect change of state


    ThreadData = (struct ThreadSocketData *)arg;
    ThreadData->Active = true;
    printf("spinning up speaker audio thread with port %d\n", ThreadData->Portid);

    //
    // setup DMA buffer
    //
    posix_memalign((void**)&SpkWriteBuffer, VALIGNMENT, SpkBufferSize);
    if (!SpkWriteBuffer)
    {
        printf("spkr write buffer allocation failed\n");
        InitError = true;
    }
    SpkReadPtr = SpkWriteBuffer + VBASE;							// offset 4096 bytes into buffer
    SpkHeadPtr = SpkWriteBuffer + VBASE;
    SpkBasePtr = SpkWriteBuffer + VBASE;
    memset(SpkWriteBuffer, 0, SpkBufferSize);

    //
    // open DMA device driver
    //
    DMAWritefile_fd = open(VSPKDMADEVICE, O_RDWR);
    if (DMAWritefile_fd < 0)
    {
        printf("XDMA write device open failed for spk data\n");
        InitError = true;
    }
	  ResetDMAStreamFIFO(eSpkCodecDMA);
    SetupFIFOMonitorChannel(eSpkCodecDMA, false);

  //
  // main processing loop
  // modified to have the same structure as outgoing threads; capable of being stopped and started.
  //
    while(1)
    {
        //
        // now released to start processing. Setup buffers.
        //
        if(SDRActive & !PrevSDRActive)                      // detect SDRActive has been asserted
            StartupCount = VSTARTUPDELAY;
        PrevSDRActive = SDRActive;

        memset(&iovecinst, 0, sizeof(struct iovec));            // clear buffers
        memset(&datagram, 0, sizeof(datagram));
        iovecinst.iov_base = &UDPInBuffer;                      // set buffer for incoming message number i
        iovecinst.iov_len = VSPEAKERAUDIOSIZE;
        datagram.msg_iov = &iovecinst;
        datagram.msg_iovlen = 1;
        datagram.msg_name = &addr_from;
        datagram.msg_namelen = sizeof(addr_from);
        //
        // receive operation thread
        //
        size = recvmsg(ThreadData->Socketid, &datagram, 0);     // get one message. If it times out, sets size=-1
        if(size < 0 && errno != EAGAIN)
        {
            perror("recvfrom fail, Speaker data");
            return EXIT_FAILURE;
        }
        if(size == VSPEAKERAUDIOSIZE)                           // we have received a packet!
        {
            if(StartupCount != 0)                                   // decrement startup message count
                StartupCount--;
            NewMessageReceived = true;
            RegVal += 1; // debug
            Depth = ReadFIFOMonitorChannel(eSpkCodecDMA, &FIFOOverflow, &FIFOOverThreshold, &FIFOUnderflow,
                                           (uint16_t *) &Current);        // read the FIFO free locations
            if((StartupCount == 0) && FIFOOverThreshold && UseDebug)
                printf("Codec speaker FIFO Overthreshold, depth now = %d\n", Current);
            if((StartupCount == 0) && FIFOUnderflow)
            {
                GlobalFIFOOverflows |= 0b00001000;
                if(UseDebug)
                    printf("Codec speaker FIFO Underflowed, depth now = %d\n", Current);
            }
    //            printf("speaker packet received; depth = %d\n", Depth);
            while (Depth < VMEMWORDSPERFRAME)       // loop till space available
            {
                usleep(1000);	// 1ms wait
                Depth = ReadFIFOMonitorChannel(eSpkCodecDMA, &FIFOOverflow, &FIFOOverThreshold, &FIFOUnderflow,
                                               (uint16_t *) &Current);    // read the FIFO free locations
                if((StartupCount == 0) && FIFOOverThreshold && UseDebug)
                    printf("Codec speaker FIFO Overthreshold, depth now = %d\n", Current);
                if((StartupCount == 0) && FIFOUnderflow)
                {
                    GlobalFIFOOverflows |= 0b00001000;
                    if(UseDebug)
                        printf("Codec speaker FIFO Underflowed, depth now = %d\n", Current);
                }
            }
            // copy sata from UDP Buffer & DMA write it
            memcpy(SpkBasePtr, UDPInBuffer + 4, VDMATRANSFERSIZE);              // copy out spk samples
    //        if(RegVal == 100)
    //            DumpMemoryBuffer(SpkBasePtr, VDMATRANSFERSIZE);
            DMAWriteToFPGA(DMAWritefile_fd, SpkBasePtr, VDMATRANSFERSIZE, VADDRSPKRSTREAMWRITE);
        }
    }
//
// close down thread
//
    close(ThreadData->Socketid);                  // close incoming data socket
    ThreadData->Socketid = 0;
    ThreadData->Active = false;                   // indicate it is closed
    return NULL;
}



