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
#include "OutDDCIQ.h"
#include "../common/saturntypes.h"
#include "OutMicAudio.h"
#include <errno.h>
#include <stdlib.h>
#include <stddef.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include "../common/saturndrivers.h"
#include "../common/hwaccess.h"




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
    for (uint32_t ddc = 0; ddc < VNUMDDC; ddc++)
    {
        UDPBuffer[ddc] = malloc(VDDCPACKETSIZE);
        DDCSampleBuffer[ddc] = malloc(DMABufferSize);
        IQReadPtr[ddc] = DDCSampleBuffer[ddc] + VBASE;		// offset 4096 bytes into buffer
        IQHeadPtr[ddc] = DDCSampleBuffer[ddc] + VBASE;
        IQBasePtr[ddc] = DDCSampleBuffer[ddc] + VBASE;
    }
    return false;
}


void FreeDynamicMemory(void)
{
    free(DMAReadBuffer);
    //
    // free the per-DDC buffers
    //
    for (uint32_t ddc = 0; ddc < VNUMDDC; ddc++)
    {
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
    uint32_t RateWord;                                          // DDC rate word from buffer
    uint32_t HdrWord;                                           // check word read form DMA's data
    uint16_t* SrcWordPtr, * DestWordPtr;                        // 16 bit read & write pointers
    uint32_t *LongWordPtr;
    uint32_t PrevRateWord;                                      // last used rate word
    uint32_t Cntr;                                              // sample word counter
    bool HeaderFound;
    uint32_t DecodeByteCount;                                   // bytes to decode
    unsigned int Current;                                   // current occupied locations in FIFO
    unsigned int StartupCount;                              // used to delay reporting of under & overflows

//
// initialise. Create memory buffers and open DMA file devices
//
    PrevRateWord = 0xFFFFFFFF;                                  // illegal value to forc re-calculation of rates
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
    HeaderFound = false;
    usleep(1000);                           // give FIFO time to stop recording 
    SetupFIFOMonitorChannel(eRXDDCDMA, false);
    ResetDMAStreamFIFO(eRXDDCDMA);
    RegisterValue = ReadFIFOMonitorChannel(eRXDDCDMA, &FIFOOverflow, &FIFOOverThreshold, &FIFOUnderflow,
                                           (uint16_t *) &Current);				// read the FIFO Depth register
    if (UseDebug)
          printf("DDC FIFO Depth register = %08x (should be ~0)\n", RegisterValue);


//
// thread loop. runs continuously until commanded by main loop to exit
// for now: add 1 RX data + mic data at 48KHz sample rate. Mic data is constant zero.
// while there is enough I/Q data, make outgoing packets;
// when not enough data, read more.
//
    while (!InitError)
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
//                    printf("enough data for packet: DDC= %d\n", ddc);
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
                        printf("Send Error, ddc=%d, errno=%d, socket id = %d\n", ddc, errno, ThreadData[ddc].Socketid);
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

            // Short wait to increase the probability the buffer hits the minimumDMATransferSize
            usleep(500);
            Depth = ReadFIFOMonitorChannel(eRXDDCDMA, &FIFOOverflow, &FIFOOverThreshold, &FIFOUnderflow,
                                           (uint16_t *) &Current);				// read the FIFO Depth register

            if((StartupCount == 0) && FIFOOverThreshold)
            {
                GlobalFIFOOverflows |= 0b00000001;
                if(UseDebug)
                    printf("RX DDC FIFO Overthreshold, depth now = %d\n", Current);
            }
            // note this could often generate a message at low sample rate because we deliberately read it down to zero.
            // this isn't a problem as we can send the data on without the code becoming blocked. so not a useful trap.
            //		printf("read: depth = %d\n", Depth);
            while (Depth < (minimumDMATransferSize / 8U)) // 8 bytes per location
            {
              usleep(1000); // 1ms wait
              Depth = ReadFIFOMonitorChannel(eRXDDCDMA, &FIFOOverflow, &FIFOOverThreshold, &FIFOUnderflow,
                                             (uint16_t *) &Current);
              if ((StartupCount == 0) && FIFOOverThreshold) {
                GlobalFIFOOverflows |= 0b00000001;
                if (UseDebug)
                  printf("RX DDC FIFO Overthreshold, depth now = %d\n", Current);
              }
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
//            DumpMemoryBuffer(DMAReadPtr, DMATransferSize);
            if(HeaderFound == false)                                                    // 1st time: look for header
                for(Cntr=16; Cntr < (DMAHeadPtr - DMAReadPtr); Cntr+=8)                  // search for rate word; ignoring 1st
                {
                    if(*(DMAReadPtr + Cntr + 7) == 0x80)
                    {
//                        printf("found header at offset=%x\n", Cntr);
                        HeaderFound = true;
                        DMAReadPtr += Cntr;                                             // point read buffer where header is 
                        break;
                    }
                }
            if (HeaderFound == false)                                        // if rate flag not set
            {
//                printf("Rate word not found when expected. rate= %08x\n", RateWord);
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
              if (*(DMAReadPtr + 7) != 0x80) {
                printf("header not found for rate word at addr %s\n", DMAReadPtr);
                exit(1);
              } else                                                                    // analyse word, then process
              {
                LongWordPtr = (uint32_t *) DMAReadPtr;                            // get 32 bit ptr
                RateWord = *LongWordPtr;                                      // read rate word

                if (RateWord != PrevRateWord) {
                  FrameLength = AnalyseDDCHeader(RateWord, DDCCounts);           // read new settings
  //                        printf("new framelength = %d\n", FrameLength);
                  PrevRateWord = RateWord;                                        // so we know its analysed
                }
                if (DecodeByteCount >= ((FrameLength + 1) * 8))             // if bytes for header & frame
                {
                  DMAReadPtr += 8;                                                // point to 1st location past rate word
                  SrcWordPtr = (uint16_t *) DMAReadPtr;                             // read sample data in 16 bit chunks
                  for (int ddc = 0; ddc < VNUMDDC; ddc++) {
                    HdrWord = DDCCounts[ddc];                                   // number of words for this DDC. reuse variable
                    if (HdrWord != 0) {
                      DestWordPtr = (uint16_t *) IQHeadPtr[ddc];
                      for (uint32_t j = 0; j < HdrWord; j++) {
                        memcpy(DestWordPtr, SrcWordPtr, 6);  // copy 48 bits
                        DestWordPtr += 3;
                        SrcWordPtr += 4;  // move to next 64-bit word
                      }
                      IQHeadPtr[ddc] += 6 * HdrWord;  // 6 bytes per sample
                    }
                  }
                  DMAReadPtr += FrameLength * 8;                                  // that's how many bytes we read out
                  DecodeByteCount -= (FrameLength + 1) * 8;
                } else {
                  break;                                                          // if not enough left, exit loop
                }
              }
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
