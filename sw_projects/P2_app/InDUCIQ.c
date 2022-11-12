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
#include <stdlib.h>
#include <stddef.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include "../common/saturnregisters.h"
#include "../common/saturndrivers.h"


#define VIQSAMPLESPERFRAME 240                      // samples per UDP frame
#define VIQSAMPLESPERMEMWORD 180                    // samples per 64 bit memory write
#define VBYTESPERSAMPLE 6							// 24 bit + 24 bit samples
#define VDMABUFFERSIZE 32768						// memory buffer to reserve
#define VALIGNMENT 4096                             // buffer alignment
#define VBASE 0x1000								// DMA start at 4K into buffer
#define VDMATRANSFERSIZE 1440                       // write 1 message at a time

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
    bool InitError = false;                                 // becomes true if we get an initialisation error
    unsigned char* IQReadPtr;								// pointer for reading out an I/Q sample
    unsigned char* IQHeadPtr;								// ptr to 1st free location in I/Q memory
    unsigned char* IQBasePtr;								// ptr to DMA location in I/Q memory
    uint32_t Depth = 0;
    int DMAWritefile_fd = -1;								// DMA read file device
    uint32_t RegisterValue;
    bool FIFOOverflow;

    ThreadData = (struct ThreadSocketData *)arg;
    ThreadData->Active = true;
    printf("spinning up DUC I/Q thread with port %d\n", ThreadData->Portid);
  
    //
    // setup DMA buffer
    //
    posix_memalign((void**)&IQWriteBuffer, VALIGNMENT, IQBufferSize);
    if (!IQWriteBuffer)
    {
        printf("I/Q TX write buffer allocation failed\n");
        InitError = true;
    }
    IQReadPtr = IQWriteBuffer + VBASE;							// offset 4096 bytes into buffer
    IQHeadPtr = IQWriteBuffer + VBASE;
    IQBasePtr = IQWriteBuffer + VBASE;
    memset(IQWriteBuffer, 0, IQBufferSize);

    //
    // open DMA device driver
    //
    DMAWritefile_fd = open(VDUCDMADEVICE, O_RDWR);
    if (DMAWritefile_fd < 0)
    {
        printf("XDMA write device open failed for TX I/Q data\n");
        InitError = true;
    }
        
//
// setup hardware
//
    EnableDUCMux(false);                                  // disable temporarily
    SetTXIQDeinterleaved(false);                          // not interleaved (at least for now!)
    ResetDUCMux();                                        // reset 64 to 48 mux
    EnableDUCMux(true);                                   // enable operation

  //
  // main processing loop
  //
    while(1)
    {
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
            return EXIT_FAILURE;
        }
        if(size == VDUCIQSIZE)
        {
            Depth = ReadFIFOMonitorChannel(eTXDUCDMA, &FIFOOverflow);           // read the FIFO free locations
            while (Depth < (VIQSAMPLESPERMEMWORD))       // loop till space available
            {
                usleep(500);								                    // 0.5ms wait
                Depth = ReadFIFOMonitorChannel(eTXDUCDMA, &FIFOOverflow);       // read the FIFO free locations
            }
            // copy sata from UDP Buffer & DMA write it
            memcpy(IQBasePtr, UDPBuffer + 4, VDMATRANSFERSIZE);                // copy out I/Q samples
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
void HandlerSetEERMode(EEREnabled)
{

}