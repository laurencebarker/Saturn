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
#include "OutDDCIQ.h"
#include <errno.h>
#include <stdlib.h>
#include <stddef.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include "../common/saturnregisters.h"
#include "../common/saturndrivers.h"
#include "../common/hwaccess.h"
#include "../common/debugaids.h"




//
// global holding the current step of C&C data. Each new USB frame updates this.
//
#define VDMABUFFERSIZE 131072						// memory buffer to reserve (4x DDC FIFO so OK)
#define VALIGNMENT 4096                             // buffer alignment
#define VBASE 0x1000									              // DMA start at 4K into buffer
#define VBASE 0x1000                                // offset into I/Q buffer for DMA to start
#define VDMATRANSFERSIZE 4096                       // read 4K at a time  initially

#define VDDCPACKETSIZE 1444
#define VIQSAMPLESPERFRAME 238                      // total I/Q samples in one DDC packet
#define VIQBYTESPERFRAME 6*VIQSAMPLESPERFRAME       // total bytes in one outgoing frame
#define VSTARTUPDELAY 100                           // 100 messages (~100ms) before reporting under or overflows

//
// strategy:
// 1. We have one DMA buffer, big enough for the largest DMA
// 2. When a DMA occurs, trafer data to separate circular buffers for each DDC
// 3. retain separate pointers into those buffers for each DDC
// 4. copy ALL DMA'd data out to the separate buffers
// 5. then loop through all DDC IQ buffers and send as many messages as possible
//


// use of IQ memory buffers as a "nearly circular" buffer:

//
// initially: data is added starting at Base pointer
// 
//               higher address
//
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 | <- IQHeadPtr: 1st free location above occupied data
//       | XXXXXXXXXX occupied XXXXXXXXXXX |
//       | XXXXXXXXXX occupied XXXXXXXXXXX |
//       | XXXXXXXXXX occupied XXXXXXXXXXX |
//       | XXXXXXXXXX occupied XXXXXXXXXXX |
//       | XXXXXXXXXX occupied XXXXXXXXXXX |
//       | XXXXXXXXXX occupied XXXXXXXXXXX |
//       | XXXXXXXXXX occupied XXXXXXXXXXX |
//       | XXXXXXXXXX occupied XXXXXXXXXXX | <- IQBasePtr, IQReadPtr
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 | <- start of memory buffer
//                 low address
//
// when there is enough data for a P2 packet, it is copied out from the bottom:


//
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 | <- IQHeadPtr: 1st free location above occupied data
//       | XXXXXXXXXX occupied XXXXXXXXXXX |
//       | XXXXXXXXXX occupied XXXXXXXXXXX |
//       | XXXXXXXXXX occupied XXXXXXXXXXX |
//       | XXXXXXXXXX occupied XXXXXXXXXXX |
//       | XXXXXXXXXX occupied XXXXXXXXXXX | <- IQReadPtr: 1st occupied location, ready to read
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 |
//       |               offset +0x1000    | <- IQBasePtr: data initially transferred here
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 | <- start of memory buffer
//                 low address
//
// then the "residue" is copied just BELOW the IQBasePtr, ready for a 
// linear DMA to be able to read the next P2 packet without a "wrap" in the middle
//
//
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 | 
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 | 
//       | XXXXXXXXXX occupied XXXXXXXXXXX |<- IQBasePtr, IQHeadPtr: 1st free location above occupied data
//       | XXXXXXXXXX occupied XXXXXXXXXXX |
//       | XXXXXXXXXX occupied XXXXXXXXXXX |
//       | XXXXXXXXXX occupied XXXXXXXXXXX |
//       | XXXXXXXXXX occupied XXXXXXXXXXX | <- IQReadPtr: 1st occupied location, ready to read
//       |                                 | <- start of memory buffer
//                 low address


//
// then more data gets added at the headptr:
// 
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 | 
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 |
//       |                                 |
//       | XXXXXXXXXX occupied XXXXXXXXXXX |<- IQHeadPtr: 1st free location above occupied data
//       | XXXXXXXXXX occupied XXXXXXXXXXX | 
//       | XXXXXXXXXX occupied XXXXXXXXXXX |<- IQBasePtr
//       | XXXXXXXXXX occupied XXXXXXXXXXX |
//       | XXXXXXXXXX occupied XXXXXXXXXXX |
//       | XXXXXXXXXX occupied XXXXXXXXXXX |
//       | XXXXXXXXXX occupied XXXXXXXXXXX | <- IQReadPtr: 1st occupied location, ready to read
//       |                                 | <- start of memory buffer
//                 low address
// 



const uint32_t minimumDMATransferSize = 4096;

//
// code to allocate and free dynamic allocated memory
// first the memory buffers:
//
uint8_t* DMAReadBuffer = NULL;								// data for DMA read from DDC
uint32_t DMABufferSize = VDMABUFFERSIZE;
unsigned char* DMAReadPtr;							        // pointer for 1st available location in DMA memory
unsigned char* DMAHeadPtr;							        // ptr to 1st free location in DMA memory
unsigned char* DMABasePtr;							        // ptr to target DMA location in DMA memory

uint8_t* UDPBuffer[VNUMDDC];                                // DDC frame buffer
uint8_t* DDCSampleBuffer[VNUMDDC];                          // buffer per DDC
unsigned char* IQReadPtr[VNUMDDC];							// pointer for reading out an I or Q sample
unsigned char* IQHeadPtr[VNUMDDC];							// ptr to 1st free location in I/Q memory
unsigned char* IQBasePtr[VNUMDDC];							// ptr to DMA location in I/Q memory


bool CreateDynamicMemory(void)                              // return true if error
{
//
// first create the buffer for DMA, and initialise its pointers
//
    posix_memalign((void**)&DMAReadBuffer, VALIGNMENT, DMABufferSize);
    DMAReadPtr = DMAReadBuffer + VBASE;		                    // offset 4096 bytes into buffer
    DMAHeadPtr = DMAReadBuffer + VBASE;
    DMABasePtr = DMAReadBuffer + VBASE;
    if (!DMAReadBuffer)
    {
        printf("I/Q read buffer allocation failed\n");
        return true;
    }
    memset(DMAReadBuffer, 0, DMABufferSize);

    //
    // set up per-DDC data structures
    //
    for (int ddc = 0; ddc < VNUMDDC; ddc++)
    {
        UDPBuffer[ddc] = malloc(VDDCPACKETSIZE);
        DDCSampleBuffer[ddc] = malloc(DMABufferSize);
        IQReadPtr[ddc] = DDCSampleBuffer[ddc] + VBASE;		// offset 4096 bytes into buffer
        IQHeadPtr[ddc] = DDCSampleBuffer[ddc] + VBASE;
        IQBasePtr[ddc] = DDCSampleBuffer[ddc] + VBASE;
    }
    return false;
}


void FreeDynamicMemory(void) {
  free(DMAReadBuffer);

  // free the per-DDC buffers
  for (int ddc = 0; ddc < VNUMDDC; ddc++) {
    free(UDPBuffer[ddc]);
    free(DDCSampleBuffer[ddc]);
  }
}


//
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
    uint32_t DMATransferSize;
    bool InitError = false;                                     // becomes true if we get an initialisation error
    
    uint32_t ResidueBytes;
    uint32_t Depth = 0;
    
    int IQReadfile_fd = -1;									    // DMA read file device
    uint32_t RegisterValue;
    bool FIFOOverflow, FIFOUnderflow, FIFOOverThreshold;

    struct ThreadSocketData *ThreadData;                        // socket etc data for each thread.
                                                                // points to 1st one
//
// variables for outgoing UDP frame
//
    struct sockaddr_in DestAddr[VNUMDDC];                       // destination address for outgoing data
    struct iovec iovecinst[VNUMDDC];                            // instance of iovec
    struct msghdr datagram[VNUMDDC];
    uint32_t SequenceCounter[VNUMDDC];                          // UDP sequence count
//
// variables for analysing a DDC frame
//
    uint32_t FrameLength;                                       // number of words per frame
    uint32_t DDCCounts[VNUMDDC];                                // number of samples per DDC in a frame
    static DDCState ddcState = {0};
    uint32_t DecodeByteCount;                                   // bytes to decode
    unsigned int Current;                                   // current occupied locations in FIFO
    unsigned int StartupCount;                              // used to delay reporting of under & overflows

//
// initialise. Create memory buffers and open DMA file devices
//
    DMATransferSize = VDMATRANSFERSIZE;                         // initial size, but can be changed
    InitError = CreateDynamicMemory();
    //
    // open DMA device driver
    //
    IQReadfile_fd = open(VDDCDMADEVICE, O_RDWR);
    if (IQReadfile_fd < 0)
    {
        printf("XDMA read device open failed for DDC data\n");
        InitError = true;
    }

    ThreadData = (struct ThreadSocketData*)arg;
    printf("spinning up outgoing I/Q thread with port %d\n", ThreadData->Portid);

    //
    // set up per-DDC data structures
    //
    for (int ddc = 0; ddc < VNUMDDC; ddc++)
    {
        SequenceCounter[ddc] = 0;                       // clear UDP packet counter
        ThreadData[ddc].Active = true;                  // set outgoing socket active
    }

//
// now initialise Saturn hardware.
// ***This is debug code at the moment. ***
// clear FIFO
// then read depth
//
//    RegisterWrite(0x1010, 0x0000002A);      // disable DDC data transfer; DDC2=test source
    SetRXDDCEnabled(false);
    usleep(1000);                           // give FIFO time to stop recording 
    SetupFIFOMonitorChannel(eRXDDCDMA, false);
    ResetDMAStreamFIFO(eRXDDCDMA);
    RegisterValue = ReadFIFOMonitorChannel(eRXDDCDMA, &FIFOOverflow, &FIFOOverThreshold, &FIFOUnderflow, &Current);				// read the FIFO Depth register
    if(UseDebug)
          printf("DDC FIFO Depth register = %08x (should be ~0)\n", RegisterValue);
    Depth=0;




//
// thread loop. runs continuously until commanded by main loop to exit
// for now: add 1 RX data + mic data at 48KHz sample rate. Mic data is constant zero.
// while there is enough I/Q data, make outgoing packets;
// when not enough data, read more.
//
    while(!InitError)
    {
        while (!SDRActive)
        {
          for (int ddc = 0; ddc < VNUMDDC; ddc++)
          {
            if (ThreadData[ddc].Cmdid & VBITCHANGEPORT)
            {
              close(ThreadData[ddc].Socketid);
              MakeSocket(&ThreadData[ddc], 0);
              ThreadData[ddc].Cmdid &= ~VBITCHANGEPORT;
            }
          }
          usleep(100);
        }
        printf("starting outgoing DDC data\n");
        StartupCount = VSTARTUPDELAY;
        //
        // initialise outgoing DDC packets - 1 per DDC
        //
        for (int ddc = 0; ddc < VNUMDDC; ddc++)
        {
            SequenceCounter[ddc] = 0;
            memcpy(&DestAddr[ddc], &reply_addr, sizeof(struct sockaddr_in));           // local copy of PC destination address (reply_addr is global)
            memset(&iovecinst[ddc], 0, sizeof(struct iovec));
            memset(&datagram[ddc], 0, sizeof(struct msghdr));
            iovecinst[ddc].iov_base = UDPBuffer[ddc];
            iovecinst[ddc].iov_len = VDDCPACKETSIZE;
            datagram[ddc].msg_iov = &iovecinst[ddc];
            datagram[ddc].msg_iovlen = 1;
            datagram[ddc].msg_name = &DestAddr[ddc];                   // MAC addr & port to send to
            datagram[ddc].msg_namelen = sizeof(struct sockaddr_in);
        }
      //
      // enable Saturn DDC to transfer data
      //
        printf("outDDCIQ: enable data transfer\n");
        SetRXDDCEnabled(true);
        while(!InitError && SDRActive)
        {

        //
        // loop through all DDC I/Q buffers.
        // while there is enough I/Q data for this DDC in local (ARM) memory, make DDC Packets
        // then put any residues at the heads of the buffer, ready for new data to come in
        //
            for (int ddc = 0; ddc < VNUMDDC; ddc++)
            {
                while ((IQHeadPtr[ddc] - IQReadPtr[ddc]) > VIQBYTESPERFRAME)
                {
//                    printf("enough data for packet: DDC= %d\n", DDC);
                    put_uint32(UDPBuffer[ddc], 0, SequenceCounter[ddc]++);  // add sequence count
                    memset(UDPBuffer[ddc] + 4, 0, 8);                                          // clear the timestamp data
                    put_uint16(UDPBuffer[ddc], 12, 24);                     // bits per sample
                    put_uint32(UDPBuffer[ddc], 14, VIQSAMPLESPERFRAME);     // I/Q samples for ths frame
                    //
                    // now add I/Q data & send outgoing packet
                    //
                    memcpy(UDPBuffer[ddc] + 16, IQReadPtr[ddc], VIQBYTESPERFRAME);
                    IQReadPtr[ddc] += VIQBYTESPERFRAME;

                    ssize_t Error;
                    Error = sendmsg(ThreadData[ddc].Socketid, &datagram[ddc], 0);
                    if(StartupCount != 0)                                   // decrement startup message count
                        StartupCount--;

                    if (Error == -1)
                    {
                        printf("Send Error, DDC=%d, errno=%d, socket id = %d\n", ddc, errno, (ThreadData+ddc)->Socketid);
                        InitError = true;
                    }
                }
              //
              // now copy any residue to the start of the buffer (before the data copy in point)
              // unless the buffer already starts at or below the base
              // if we do a copy, the 1st free location is always base addr
              //
              ResidueBytes = IQHeadPtr[ddc] - IQReadPtr[ddc];
              //		printf("Residue = %d bytes\n",ResidueBytes);
              if (IQReadPtr[ddc] > IQBasePtr[ddc])                                // move data down
              {
                if (ResidueBytes != 0)    // if there is residue to move
                {
                  memcpy(IQBasePtr[ddc] - ResidueBytes, IQReadPtr[ddc], ResidueBytes);
                  IQReadPtr[ddc] = IQBasePtr[ddc] - ResidueBytes;
                } else {
                  IQReadPtr[ddc] = IQBasePtr[ddc];
                }
                IQHeadPtr[ddc] = IQBasePtr[ddc];                            // ready for new data at base
              }
            }
            //
            // P2 packet sending complete.There are no DDC buffers with enough data to send out.
            // bring in more data by DMA if there is some, else sleep for a while and try again
            // we have the same issue with DMA: a transfer isn't exactly aligned to the amount we can read out 
            // according to the DDC settings. So we either need to have the part-used DDC transfer variables
            // persistent across DMAs, or we need to recognise an incomplete fragment of a frame as such
            // and copy it like we do with IQ data so the next readout begins at a new frame
            // the latter approach seems easier!
            //
            Depth = ReadFIFOMonitorChannel(eRXDDCDMA, &FIFOOverflow, &FIFOOverThreshold, &FIFOUnderflow, &Current);				// read the FIFO Depth register

            if((StartupCount == 0) && FIFOOverThreshold)
            {
                GlobalFIFOOverflows |= 0b00000001;
                if(UseDebug)
                    printf("RX DDC FIFO Overthreshold, depth now = %d\n", Current);
            }
// note this could often generate a message at low sample rate because we deliberately read it down to zero.
// this isn't a problem as we can send the data on without the code becoming blocked. so not a useful trap.
//            if((StartupCount == 0) && FIFOUnderflow)
//                 printf("RX DDC FIFO Underflowed, depth now = %d\n", Current);
            //		printf("read: depth = %d\n", Depth);

            Depth = ReadFIFOMonitorChannel(eRXDDCDMA, &FIFOOverflow, &FIFOOverThreshold, &FIFOUnderflow, &Current);
            if ((StartupCount == 0) && FIFOOverThreshold) {
              GlobalFIFOOverflows |= 0b00000001;
              if (UseDebug)
                printf("RX DDC FIFO Overthreshold, depth now = %d\n", Current);
            }
            while (Depth < (minimumDMATransferSize / 8U))      // 8 bytes per location
            {
              usleep(5000);                // 5ms wait
              Depth = ReadFIFOMonitorChannel(eRXDDCDMA, &FIFOOverflow, &FIFOOverThreshold, &FIFOUnderflow, &Current);
              if ((StartupCount == 0) && FIFOOverThreshold) {
                GlobalFIFOOverflows |= 0b00000001;
                if (UseDebug)
                  printf("RX DDC FIFO Overthreshold, depth now = %d\n", Current);
              }
//                if((StartupCount == 0) && FIFOUnderflow)
//                    printf("RX DDC FIFO Underflowed, depth now = %d\n", Current);
             }
//            printf("DDC DMA read %d bytes from destination to base\n", DMATransferSize);
            if(Depth > 4096)
                DMATransferSize = 32768;
            else if(Depth > 2048)
                DMATransferSize = 16384;
            else if(Depth > 1024)
                DMATransferSize = 8192;
            else
                DMATransferSize = 4096;

            DMAReadFromFPGA(IQReadfile_fd, DMAHeadPtr, DMATransferSize, VADDRDDCSTREAMREAD);
            DMAHeadPtr += DMATransferSize;

            //
            // find header: may not be the 1st word
            //
            uint64_t rateWordWithHeader;
            bool headerFound = false;

            // Search for the header
            for (uint32_t i = 16; i < (DMAHeadPtr - DMAReadPtr); i += 8) {
              rateWordWithHeader = *((uint64_t*)(DMAReadPtr + i));
              if ((rateWordWithHeader & (0x80ULL << (7 * 8))) != 0) {
                DMAReadPtr += i;
                headerFound = true;
                break;
              }
            }

            if (!headerFound) {
              printf("Rate word not found when expected.\n");
              InitError = true;
              exit(1);
            }

            //
            // finally copy data to DMA buffers according to the embedded DDC rate words
            // the 1st word is pointed by DMAReadPtr and it should point to a DDC rate word
            // search for it if not!
            // (it should always be left in that state).
            // the top half of the 1st 64 bit word should be 0x8000
            // and that is located in the 2nd 32 bit location.
            // assume that DMA is > 1 frame.
//            printf("headptr = %x readptr = %x\n", DMAHeadPtr, DMAReadPtr);
            DecodeByteCount = DMAHeadPtr - DMAReadPtr;
            while (DecodeByteCount >= 16)                       // minimum size to try!
            {
              rateWordWithHeader = *((uint64_t*)DMAReadPtr);
              if ((rateWordWithHeader & (0x80ULL << (7 * 8))) == 0) {
                // Header is offset by 7 bytes
                printf("header not found for rate word at addr %s\n", DMAReadPtr);
                exit(1);
              }
              uint32_t RateWord = (uint32_t)rateWordWithHeader; // extract rate word

              // Update DDC state only if RateWord has changed
              if (RateWord != ddcState.lastRateWord) {
                FrameLength = AnalyseDDCHeaderAndUpdateActive(RateWord, DDCCounts, &ddcState);
//                      printf("new framelength = %d\n", FrameLength);
              }

              if (DecodeByteCount >= ((FrameLength + 1) * 8))             // if bytes for header & frame
              {
                  //THEN COPY DMA DATA TO I / Q BUFFERS
                  DMAReadPtr += 8;                                                // point to 1st location past rate word
                  processDDCData(DMAReadPtr, IQHeadPtr, &ddcState);

                  DMAReadPtr += FrameLength * 8;                                  // that's how many bytes we read out
                  DecodeByteCount -= (FrameLength + 1) * 8;
              }
              else
                  break;                                                          // if not enough left, exit loop

            }
            //
            // now copy any residue to the start of the buffer (before the data copy in point)
            // unless the buffer already starts at or below the base
            // if we do a copy, the 1st free location is always base addr
            //
            ResidueBytes = DMAHeadPtr - DMAReadPtr;
            //		printf("Residue = %d bytes\n",ResidueBytes);
            if (DMAReadPtr > DMABasePtr)                                // move data down
            {
                if (ResidueBytes != 0) 		// if there is residue to move
                {
                    memcpy(DMABasePtr - ResidueBytes, DMAReadPtr, ResidueBytes);
                    DMAReadPtr = DMABasePtr - ResidueBytes;
                }
                else
                    DMAReadPtr = DMABasePtr;
                DMAHeadPtr = DMABasePtr;                            // ready for new data at base
            }
        }     // end of while(!InitError) loop
    }

//
// tidy shutdown of the thread
//
    printf("shutting down DDC outgoing thread\n");
    close(ThreadData->Socketid); 
    ThreadData->Active = false;                   // signal closed
    FreeDynamicMemory();
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
// arguably don't need this, as it finds out from the embedded data in the DDC stream
//
void HandlerCheckDDCSettings(void)
{

}


static void processDDCData(const uint8_t *readPtr, uint8_t **headPtr, const DDCState *state) {
  const uint8_t *srcPtr = readPtr;

  for (int i = 0; i < state->activeCount; i++) {
    int ddc = state->activeDDCs[i].ddc_index;
    uint32_t sampleCount = state->activeDDCs[i].sample_count;
    uint8_t *destPtr = headPtr[ddc];

    copyDDCData(srcPtr, destPtr, sampleCount);

    headPtr[ddc] += sampleCount * 6;  // Update IQHeadPtr
    srcPtr += sampleCount * 8;  // Move to the next DDC's data
  }
}

static uint32_t AnalyseDDCHeaderAndUpdateActive(uint32_t RateWord, uint32_t* ddcCounts, DDCState* state) {
  uint32_t Total = AnalyseDDCHeader(RateWord, ddcCounts);

  state->activeCount = 0;
  for (int ddc = 0; ddc < VNUMDDC; ddc++) {
    if (ddcCounts[ddc] > 0) {
      state->activeDDCs[state->activeCount].ddc_index = ddc;
      state->activeDDCs[state->activeCount].sample_count = ddcCounts[ddc];
      state->activeCount++;
    }
  }

  state->lastRateWord = RateWord;
  return Total;
}

static void copyDDCData(const uint8_t* srcPtr, uint8_t* destPtr, uint32_t sampleCount)
{
  for (uint32_t i = 0; i < sampleCount; i++)
  {
    // Copy 48 bits (6 bytes) of sample data
    memcpy(destPtr, srcPtr, 6);

    // Move pointers
    destPtr += 6;
    srcPtr += 8;  // Skip 16 bits where there's no data
  }
}