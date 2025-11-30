/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// InDUCIQ.c:
//
// handle "incoming DUC I/Q" message
//
//////////////////////////////////////////////////////////////

#include "threaddata.h"
#include <stdint.h>
#include "../common/saturntypes.h"
#include "InDUCIQ.h"
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
#include <pthread.h>
#include <syscall.h>




#define VIQSAMPLESPERFRAME 240                      // samples per UDP frame
#define VMEMWORDSPERFRAME 180                       // memory writes per UDP frame
#define VBYTESPERSAMPLE 6							// 24 bit + 24 bit samples
#define VDMABUFFERSIZE 32768						// memory buffer to reserve
#define VALIGNMENT 4096                             // buffer alignment
#define VBASE 0x1000								// DMA start at 4K into buffer
#define VDMATRANSFERSIZE 1440                       // write 1 message at a time
#define VSTARTUPDELAY 100                           // 100 messages (~100ms) before reporting under or overflows

//
// listener thread for incoming DUC I/Q packets
// planned strategy: just DMA spkr data when available; don't copy and DMA a larger amount.
// if sufficient FIFO data available: DMA that data and transfer it out. 
// if it turns out to be too inefficient, we'll have to try larger DMA.
//
void *IncomingDUCIQ(void *arg)                          // listener thread
{
    struct ThreadSocketData *ThreadData;                  // socket etc data for this thread
    struct sockaddr_in addr_from;                         // holds MAC address of source of incoming messages
    uint8_t UDPInBuffer[VDUCIQSIZE];                      // incoming buffer
    struct iovec iovecinst;                               // iovcnt buffer - 1 for each outgoing buffer
    struct msghdr datagram;                               // multiple incoming message header
    int size;                                             // UDP datagram length

                                                          //
// variables for DMA buffer 
//
    uint8_t* IQWriteBuffer = NULL;							// data for DMA to write to DUC
    uint32_t IQBufferSize = VDMABUFFERSIZE;
    unsigned char* IQBasePtr;								// ptr to DMA location in I/Q memory
    uint32_t Depth = 0;
    int DMAWritefile_fd = -1;								// DMA read file device
    bool FIFOOverflow, FIFOUnderflow, FIFOOverThreshold;
    uint32_t Cntr;                                          // sample counter
    uint8_t* SrcPtr;                                        // pointer to data from Thetis
    uint8_t* DestPtr;                                       // pointer to DMA buffer data
    unsigned int Current;                                   // current occupied locations in FIFO
    unsigned int StartupCount;                              // used to delay reporting of under & overflows
    bool PrevSDRActive = false;                             // used to detect change of state

    ThreadData = (struct ThreadSocketData *)arg;
    ThreadData->Active = true;
    printf("spinning up DUC I/Q thread with port %d, pid=%ld\n", ThreadData->Portid, syscall(SYS_gettid));
  
    //
    // setup DMA buffer
    //
    posix_memalign((void**)&IQWriteBuffer, VALIGNMENT, IQBufferSize);
    if (!IQWriteBuffer)
        printf("I/Q TX write buffer allocation failed\n");
    IQBasePtr = IQWriteBuffer + VBASE;
    memset(IQWriteBuffer, 0, IQBufferSize);

    //
    // open DMA device driver
    // opened write only to accommodate potential use of a different XDMA device driver
    //
    DMAWritefile_fd = open(VDUCDMADEVICE, O_WRONLY);
    if (DMAWritefile_fd < 0)
        printf("XDMA write device open failed for TX I/Q data\n");
        
//
// setup hardware
//
    EnableDUCMux(false);                                  // disable temporarily
    SetTXIQDeinterleaved(false);                          // not interleaved (at least for now!)
    ResetDUCMux();                                        // reset 64 to 48 mux
    ResetDMAStreamFIFO(eTXDUCDMA);
    SetupFIFOMonitorChannel(eTXDUCDMA, false);
    EnableDUCMux(true);                                   // enable operation

  //
  // main processing loop
  //
    while(1)
    {
        if(SDRActive & !PrevSDRActive)                      // detect SDRActive has been asserted
            StartupCount = VSTARTUPDELAY;
        PrevSDRActive = SDRActive;

        memset(&iovecinst, 0, sizeof(struct iovec));
        memset(&datagram, 0, sizeof(datagram));
        iovecinst.iov_base = &UDPInBuffer;                  // set buffer for incoming message number i
        iovecinst.iov_len = VDUCIQSIZE;
        datagram.msg_iov = &iovecinst;
        datagram.msg_iovlen = 1;
        datagram.msg_name = &addr_from;
        datagram.msg_namelen = sizeof(addr_from);
        size = recvmsg(ThreadData->Socketid, &datagram, 0);         // get one message. If it times out, ges size=-1
        if(size < 0 && errno != EAGAIN)
        {
            perror("recvfrom fail, TX I/Q data");
            return NULL;
        }
        if(size == VDUCIQSIZE)
        {
            if(StartupCount != 0)                                   // decrement startup message count
                StartupCount--;
            NewMessageReceived = true;
            Depth = ReadFIFOMonitorChannel(eTXDUCDMA, &FIFOOverflow, &FIFOOverThreshold, &FIFOUnderflow, &Current);           // read the FIFO free locations
            if((StartupCount == 0) && FIFOOverThreshold && UseDebug)
                printf("TX DUC FIFO Overthreshold, depth now = %d\n", Current);

            if((StartupCount == 0) && FIFOUnderflow)
            {
                atomic_fetch_or(&GlobalFIFOOverflows, 0b00000100);
                if(UseDebug)
                    printf("TX DUC FIFO Underflowed, depth now = %d\n", Current);
            }

            while (Depth < VMEMWORDSPERFRAME)       // loop till space available
            {
                usleep(500);								                    // 0.5ms wait
                Depth = ReadFIFOMonitorChannel(eTXDUCDMA, &FIFOOverflow, &FIFOOverThreshold, &FIFOUnderflow, &Current);       // read the FIFO free locations
                if((StartupCount == 0) && FIFOOverThreshold && UseDebug)
                    printf("TX DUC FIFO Overthreshold, depth now = %d\n", Current);
                if((StartupCount == 0) && FIFOUnderflow)
                {
                    atomic_fetch_or(&GlobalFIFOOverflows, 0b00000100);
                    if(UseDebug)
                        printf("TX DUC FIFO Underflowed, depth now = %d\n", Current);
                }
            }
            // copy data from UDP Buffer & DMA write it
//            memcpy(IQBasePtr, UDPInBuffer + 4, VDMATRANSFERSIZE);                // copy out I/Q samples
            // need to swap I & Q samples on replay
            SrcPtr = (uint8_t *) (UDPInBuffer + 4);
            DestPtr = (uint8_t *) IQBasePtr;
            for (Cntr=0; Cntr < VIQSAMPLESPERFRAME; Cntr++)                     // samplecounter
            {
                *DestPtr++ = *(SrcPtr+3);                           // get I sample (3 bytes)
                *DestPtr++ = *(SrcPtr+4);
                *DestPtr++ = *(SrcPtr+5);
                *DestPtr++ = *(SrcPtr+0);                           // get Q sample (3 bytes)
                *DestPtr++ = *(SrcPtr+1);
                *DestPtr++ = *(SrcPtr+2);
                SrcPtr += 6;                                        // point at next source sample
            }
            DMAWriteToFPGA(DMAWritefile_fd, IQBasePtr, VDMATRANSFERSIZE, VADDRDUCSTREAMWRITE);
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


//
// HandlerSetEERMode (bool EEREnabled)
// enables amplitude restoration mode. Generates envelope output alongside I/Q samples.
// NOTE hardware does not properly support this yet!
// TX FIFO must be empty. Stop multiplexer; set bit; restart
// 
void HandlerSetEERMode(__attribute__((unused)) bool EEREnabled)
{
}