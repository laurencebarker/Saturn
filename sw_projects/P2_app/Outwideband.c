/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
// derived from Pavel Demin code 
//
// OutWideband.h:
//
// header: handle "outgoing wideband data" message
//
//////////////////////////////////////////////////////////////

#include "threaddata.h"
#include <stdint.h>
#include "../common/saturntypes.h"
#include "OutHighPriority.h"
#include <errno.h>
#include <stdlib.h>
#include <stddef.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include "../common/saturnregisters.h"
#include "../common/hwaccess.h"
#include "../common/debugaids.h"


//
// global holding the current step of C&C data. Each new USB frame updates this.
//
#define VDMABUFFERSIZE 65536						            // memory buffer to reserve (2x wideband FIFO size)
#define VALIGNMENT 4096                             // buffer alignment

#define VWBPACKETSIZE 1028
#define VWBSAMPLESPERFRAME 512                      // total wideband ADC samples in one WB packet
#define VWBBYTESPERFRAME 2*VWBSAMPLESPERFRAME       // total bytes in one outgoing frame
#define VSTARTUPDELAY 100                           // 100 messages (~100ms) before reporting under or overflows
#define VNUMWBADC 2                                 // number of ADC that WB data can be collected for


//
// strategy:
// 1. We have one DMA buffer, big enough for the largest DMA from the wideband FIFO
// 2. On startup: turn off the IP and clear the FIFO if any data in it. 
// 3. wideband IP started; it periodically writes defined sample count to FIFO
// 4. When write complete, a status flag is set; one for each ADC
// 5. when a flag is set, DMA out the data then write the bit to say "data transferred"
// 6. break data into N outgoing packets and send to Thetis over UDP
// 7. when the wideband settings change: stop operation; clear FIFO; setup new settings & restart
// 8. when exiting: turn off the IP.
//






//
// code to allocate and free dynamic allocated memory
// first the memory buffers:
//
uint8_t* WBDMAReadBuffer = NULL;								// data for DMA read from DDC
uint32_t WBDMABufferSize = VDMABUFFERSIZE;
unsigned char* WBDMAReadPtr;							        // pointer for 1st available location in DMA memory

uint8_t* WBUDPBuffer[VNUMDDC];                                // DDC frame buffer


//
// create dynamically allocated memory at startup
//
bool CreateWBDynamicMemory(void)                              // return true if error
{
    uint32_t ADC;
    bool Result = false;
//
// first create the buffer for DMA, and initialise its pointers
//
    posix_memalign((void**)&WBDMAReadBuffer, VALIGNMENT, WBDMABufferSize);
    WBDMAReadPtr = WBDMAReadBuffer;		                    // offset 4096 bytes into buffer
    if (!WBDMAReadBuffer)
    {
        printf("Wideband read buffer allocation failed\n");
        Result = true;
    }
    memset(WBDMAReadBuffer, 0, WBDMABufferSize);

    //
    // set up per-Wideband ADC data structures
    //
    for (ADC = 0; ADC < VNUMWBADC; ADC++)
    {
        WBUDPBuffer[ADC] = malloc(VWBPACKETSIZE);
    }
    return Result;
}


void FreeWBDynamicMemory(void)
{
    uint32_t ADC;

    free(WBDMAReadBuffer);
    //
    // free the per-DDC buffers
    //
    for (ADC = 0; ADC < VNUMDDC; ADC++)
    {
        free(WBUDPBuffer[ADC]);
    }
}



//
// set parameters from SDR for wideband data collect
// paramters as transferred in general packet to SDR
//
void SetWidebandParams(uint8_t Enables, uint16_t SampleCount, uint8_t SampleSize, uint8_t Rate, uint8_t PacketCount)
{
//  SetWidebandEnable(eADC1, (bool)(Enables&1));
//  SetWidebandEnable(eADC2, (bool)(Enables&2));
  SetWidebandSampleCount(SampleCount);
  SetWidebandUpdateRate(Rate);
}



//
// this runs as its own thread to send outgoing wideband data
// thread initiated after a "Start" command
// will be instructed to stop & exit by main loop setting enable_thread to 0
// this code signals thread terminated by setting active_thread = 0
// substantially similar to outgoing DDC thread
//
void *OutgoingWidebandSamples(void *arg)
{
//
// memory buffers
//
    uint32_t WBDMATransferSize;
    bool InitError = false;                                     // becomes true if we get an initialisation error
    
    uint32_t Depth = 0;
    
    uint32_t RegisterValue;
    bool FIFOOverflow, FIFOUnderflow, FIFOOverThreshold;
    int ADC;                                                    // iterator

    struct ThreadSocketData *ThreadData;                        // socket etc data for each thread.
                                                                // points to 1st one
//
// variables for outgoing UDP frame
//
    struct sockaddr_in DestAddr[VNUMWBADC];                     // destination address for outgoing data
    struct iovec iovecinst[VNUMWBADC];                          // instance of iovec
    struct msghdr datagram[VNUMWBADC];
    uint32_t SequenceCounter[VNUMWBADC];                        // UDP sequence count
    
    unsigned int StartupCount;

//
// initialise. Create memory buffers and open DMA file devices
//
    InitError = CreateWBDynamicMemory();
    //
    // note we re-use the DMA device for MIC samples
    //

    ThreadData = (struct ThreadSocketData*)arg;
    printf("spinning up outgoing Wideband sample thread with port %d\n", ThreadData->Portid);

    //
    // set up per-ADC data structures
    //
    for (ADC = 0; ADC < VNUMWBADC; ADC++)
    {
        SequenceCounter[ADC] = 0;                           // clear UDP packet counter
        (ThreadData + ADC)->Active = true;                  // set outgoing socket active
    }



//
// now initialise Saturn wideband hardware.
// turn off wideband capture, and clear FIFO
// then read depth
//


//
// thread loop. runs continuously until commanded by main loop to exit
// while there is wideband data, make outgoing packets;
//
    while(!InitError)
    {
        while(!SDRActive)
        {
            for (ADC=0; ADC < VNUMWBADC; ADC++)
                if((ThreadData+ADC) -> Cmdid & VBITCHANGEPORT)
                {
                    close((ThreadData+ADC) -> Socketid);                      // close old socket, open new one
                    MakeSocket((ThreadData + ADC), 0);                        // this binds to the new port.
                    (ThreadData + ADC) -> Cmdid &= ~VBITCHANGEPORT;           // clear command bit
                }
            usleep(100);
        }
        printf("starting outgoing Wideband data\n");
        StartupCount = VSTARTUPDELAY;
        //
        // initialise outgoing WB packets - 1 per ADC
        //
        for (ADC = 0; ADC < VNUMWBADC; ADC++)
        {
            SequenceCounter[ADC] = 0;
            memcpy(&DestAddr[ADC], &reply_addr, sizeof(struct sockaddr_in));           // local copy of PC destination address (reply_addr is global)
            memset(&iovecinst[ADC], 0, sizeof(struct iovec));
            memset(&datagram[ADC], 0, sizeof(struct msghdr));
            iovecinst[ADC].iov_base = WBUDPBuffer[ADC];
            iovecinst[ADC].iov_len = VWBPACKETSIZE;
            datagram[ADC].msg_iov = &iovecinst[ADC];
            datagram[ADC].msg_iovlen = 1;
            datagram[ADC].msg_name = &DestAddr[ADC];                   // MAC addr & port to send to
            datagram[ADC].msg_namelen = sizeof(DestAddr);
        }
      //
      // enable Saturn WB IP to transfer data
      //
        printf("outDDCIQ: enable data transfer\n");
        while(!InitError && SDRActive)
        {
        }     // end of while(!InitError&& SDRActive) loop
    } //end of while(!InitError)

//
// tidy shutdown of the thread
//
    printf("shutting down Wideband outgoing thread\n");
    close(ThreadData->Socketid); 
    ThreadData->Active = false;                   // signal closed
    FreeWBDynamicMemory();
    return NULL;
}