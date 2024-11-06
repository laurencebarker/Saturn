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
bool CreatewbDynamicMemory(void)                              // return true if error
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


void FreewbDynamicMemory(void)
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
//
void *OutgoingWidebandSamples(void *arg)
{
    while(1)
    {

    }
}