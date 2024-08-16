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
#include "InDUCIQ.h"
#include <arm_neon.h>
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

#if defined(__aarch64__) || (defined(__arm__) && defined(__ARM_NEON))
#define HAS_NEON 1
#else
#define HAS_NEON 0
#endif

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
    ssize_t size;                                             // UDP datagram length

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
    bool FIFOOverflow, FIFOUnderflow, FIFOOverThreshold;
    uint32_t Cntr;                                          // sample counter
    uint8_t* SrcPtr;                                        // pointer to data from Thetis
    uint8_t* DestPtr;                                       // pointer to DMA buffer data
    unsigned int Current;                                   // current occupied locations in FIFO
    unsigned int StartupCount;                              // used to delay reporting of under & overflows
    bool PrevSDRActive = false;                             // used to detect change of state

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
            return EXIT_FAILURE;
        }
        if(size == VDUCIQSIZE)
        {
            if(StartupCount != 0)                                   // decrement startup message count
                StartupCount--;
            NewMessageReceived = true;
            usleep(500); // wait at least 0.5ms before checking, to increase the likelihood there's enough space ready
            Depth = ReadFIFOMonitorChannel(eTXDUCDMA, &FIFOOverflow, &FIFOOverThreshold, &FIFOUnderflow,
                                           (uint16_t *) &Current);           // read the FIFO free locations
            if((StartupCount == 0) && FIFOOverThreshold && UseDebug)
                printf("TX DUC FIFO Overthreshold, depth now = %d\n", Current);

            if((StartupCount == 0) && FIFOUnderflow)
            {
                GlobalFIFOOverflows |= 0b00000100;
                if(UseDebug)
                    printf("TX DUC FIFO Underflowed, depth now = %d\n", Current);
            }

            while (Depth < VMEMWORDSPERFRAME)       // loop till space available
            {
              usleep(2000); // 2ms wait
              Depth = ReadFIFOMonitorChannel(eTXDUCDMA, &FIFOOverflow, &FIFOOverThreshold, &FIFOUnderflow,
                                             (uint16_t *) &Current);
              if ((StartupCount == 0) && FIFOOverThreshold && UseDebug)
                printf("TX DUC FIFO Overthreshold, depth now = %d\n", Current);
              if ((StartupCount == 0) && FIFOUnderflow) {
                GlobalFIFOOverflows |= 0b00000100;
                if (UseDebug)
                  printf("TX DUC FIFO Underflowed, depth now = %d\n", Current);
              }
            }
            transferIQSamples(UDPInBuffer, IQBasePtr, DMAWritefile_fd);
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


// Copy data from UDP Buffer & DMA write it
static void transferIQSamples(const uint8_t* UDPInBuffer, uint8_t* IQBasePtr, int DMAWritefile_fd) {
#if HAS_NEON
  transferIQSamples_SIMD(UDPInBuffer, IQBasePtr, DMAWritefile_fd);
#else
  transferIQSamples_generic(UDPInBuffer, IQBasePtr, DMAWritefile_fd);
#endif
}


// SIMD implementation for ARM v8 and ARM v7 with NEON
#if HAS_NEON
static void transferIQSamples_SIMD(const uint8_t* UDPInBuffer, uint8_t* IQBasePtr, int DMAWritefile_fd)
{
  const uint8_t* srcPtr = UDPInBuffer + 4;
  uint8_t* destPtr = IQBasePtr;

  // Create a mask for the first 96 bits (12 bytes)
  const uint8x16_t mask = {255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 0, 0, 0, 0};

  // Process 2 IQ samples (12 bytes) per iteration
  // Process all 240 samples in 120 iterations: 2 IQ samples (12 bytes) per iteration
  for (int i = 0; i < 120; i++)
  {
    // Load 16 bytes (2 IQ samples + 4 extra bytes) into a 128-bit register
    uint8x16_t input = vld1q_u8(srcPtr);

    // Swap I and Q samples
    uint8x16_t swapped = vqtbl1q_u8(input,
                                    (uint8x16_t) {3, 4, 5, 0, 1, 2, 9, 10, 11, 6, 7, 8, 12, 13, 14, 15});

    // Apply mask to keep only the first 12 bytes
    uint8x16_t masked = vandq_u8(swapped, mask);

    // Store the first 12 bytes of the result
    vst1q_u8(destPtr, masked);

    // Move to the next block
    srcPtr += 12;
    destPtr += 12;
  }

  DMAWriteToFPGA(DMAWritefile_fd, IQBasePtr, VDMATRANSFERSIZE, VADDRDUCSTREAMWRITE);
}
#endif

// Generic implementation for non-NEON platforms
static void transferIQSamples_generic(const uint8_t* UDPInBuffer, uint8_t* IQBasePtr, int DMAWritefile_fd) {
  const uint8_t* srcPtr = UDPInBuffer + 4;
  uint8_t* destPtr = IQBasePtr;

  // Need to swap I & Q samples on replay
  for (size_t i = 0; i < VIQSAMPLESPERFRAME; i++) {
    // Copy Q sample (3 bytes).
    // We copy Q first so that we read from srcPtr first, making the subsequent read from srcPtr + 3 a cache hit.
    memcpy(destPtr + 3, srcPtr, 3);

    // Copy I sample (3 bytes)
    memcpy(destPtr, srcPtr + 3, 3);

    // Move to the next source sample
    destPtr += 6;
    srcPtr += 6;
  }

  DMAWriteToFPGA(DMAWritefile_fd, IQBasePtr, VDMATRANSFERSIZE, VADDRDUCSTREAMWRITE);
}


//
// HandlerSetEERMode (bool EEREnabled)
// enables amplitude restoration mode. Generates envelope output alongside I/Q samples.
// NOTE hardware does not properly support this yet!
// TX FIFO must be empty. Stop multiplexer; set bit; restart
// 
void HandlerSetEERMode(bool EEREnabled)
{

}