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
    uint8_t* DMAReadBuffer = NULL;								// data for DMA read from DDC
    uint32_t DMABufferSize = VDMABUFFERSIZE;
    unsigned char* DMAReadPtr;							        // pointer for 1st available location in DMA memory
    unsigned char* DMAHeadPtr;							        // ptr to 1st free location in DMA memory
    unsigned char* DMABasePtr;							        // ptr to target DMA location in DMA memory
    unit32_t DMATransferSize;
    bool InitError = false;                                     // becomes true if we get an initialisation error
    
    uint8_t* DDCSampleBuffer[VNUMDDC];                          // buffer per DDC
    unsigned char* IQReadPtr[VNUMDDC];							// pointer for reading out an I or Q sample
    unsigned char* IQHeadPtr[VNUMDDC];							// ptr to 1st free location in I/Q memory
    unsigned char* IQBasePtr[VNUMDDC];							// ptr to DMA location in I/Q memory
    uint32_t ResidueBytes;
    uint32_t Depth = 0;
    
    int IQReadfile_fd = -1;									    // DMA read file device
    uint32_t RegisterValue;
    bool FIFOOverflow;
    int DDC;                                                    // iterator

    struct ThreadSocketData *ThreadData;                        // socket etc data for each thread.
                                                                // points to 1st one
//
// variables for outgoing UDP frame
//
    struct sockaddr_in DestAddr[VNUMDDC];                       // destination address for outgoing data
    struct iovec iovecinst[VNUMDDC];                            // instance of iovec
    struct msghdr datagram[VNUMDDC];
    uint8_t* UDPBuffer[VNUMDDC];                                // DDC frame buffer
    uint32_t SequenceCounter[VNUMDDC];                          // UDP sequence count
//
// variables for analysing a DDC frame
//
    uint32_t FrameLength;                                       // number of words per frame
    uint32_t DDCCounts[VNUMDDC];                                // number of samples per DDC in a frame
    uint32_t RateWord;                                          // DDC rate word from buffer
    uint32_t HdrWord;                                           // check word read form DMA's data
    uint16_t* SrcWordPtr, * DestWordPtr;                        // 16 bit read & write pointers
    uint32_t LongWordPtr;
    uint32_t PrevRateWord;                                      // last used rate word
    bool EnoughData;
    uint32_t Cntr;                                              // sample word counter

//
// initialise. Create memory buffers and open DMA file devices
//
    PrevRateWord = 0xFFFFFFFF;                                  // illegal value to forc re-calculation of rates
    DMATransferSize = VDMATRANSFERSIZE;                         // initial size, but can be changed
    posix_memalign((void**)&DMAReadBuffer, VALIGNMENT, DMABufferSize);
    DMAReadPtr = DMAReadBuffer + VBASE;		                    // offset 4096 bytes into buffer
    DMAHeadPtr = DMAReadBuffer + VBASE;
    DMABasePtr = DMAReadBuffer + VBASE;
    if (!DMAReadBuffer)
    {
        printf("I/Q read buffer allocation failed\n");
        InitError = true;
    }
    memset(DMAReadBuffer, 0, DMABufferSize);
    //
    // open DMA device driver
    //    this will probably have to move, as there won't be enough of them!
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
    for (DDC = 0; DDC < VNUMDDC; DDC++)
    {
        SequenceCounter[DDC] = 0;                           // clear UDP packet counter
        UDPBuffer[DDC] = malloc(VDDCPACKETSIZE);
        DDCSampleBuffer[DDC] = malloc(DMABufferSize);
        IQReadPtr[DDC] = DDCSampleBuffer[DDC] + VBASE;		// offset 4096 bytes into buffer
        IQHeadPtr[DDC] = DDCSampleBuffer[DDC] + VBASE;
        IQBasePtr[DDC] = DDCSampleBuffer[DDC] + VBASE;
        (ThreadData + DDC)->Active = true;                  // set outgoing socket active
    }



//
// now initialise Saturn hardware.
// ***This is debug code at the moment. ***
// clear FIFO
// then read depth
//
    SetupFIFOMonitorChannel(eRXDDCDMA, false);
    ResetDMAStreamFIFO(eRXDDCDMA);
    RegisterValue = ReadFIFOMonitorChannel(eRXDDCDMA, &FIFOOverflow);				// read the FIFO Depth register
	printf("FIFO Depth register = %08x (should be 0)\n", RegisterValue);
	Depth=0;


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
            for (DDC=0; DDC < VNUMDDC; DDC++)
                if((ThreadData+DDC) -> Cmdid & VBITCHANGEPORT)
                {
                    close((ThreadData+DDC) -> Socketid);                      // close old socket, open new one
                    MakeSocket((ThreadData + DDC), 0);                        // this binds to the new port.
                    (ThreadData + DDC) - >Cmdid &= ~VBITCHANGEPORT;           // clear command bit
                }
                usleep(100);
        }
        printf("starting outgoing data\n");
        //
        // initialise outgoing DDC packets - 1 per DDC
        //
        for (DDC = 0; DDC < VNUMDDC; DDC++)
        {
            SequenceCounter[DDC] = 0;
            memcpy(&DestAddr[DDC], &reply_addr, sizeof(struct sockaddr_in));           // local copy of PC destination address (reply_addr is global)
            memset(&iovecinst[DDC], 0, sizeof(struct iovec));
            memset(&datagram[DDC], 0, sizeof(datagram));
            iovecinst[DDC].iov_base = UDPBuffer;
            iovecinst[DDC].iov_len = VDDCPACKETSIZE;
            datagram[DDC].msg_iov = &iovecinst;
            datagram[DDC].msg_iovlen = 1;
            datagram[DDC].msg_name = &DestAddr;                   // MAC addr & port to send to
            datagram[DDC].msg_namelen = sizeof(DestAddr);
        }

      //
      // enable Saturn DDC to transfer data
      //
        SetDDCInterleaved(0, false);
        SetRXDDCEnabled(true);
        printf("enabled DDC\n");
        while(!InitError && SDRActive)
        {

        //
        // loop through all DDC I/Q buffers.
        // while there is enough I/Q data for this DDC in local (ARM) memory, make DDC Packets
        // then put any residues at the heads of the buffer, ready for new data to come in
        //
            for (DDC = 0; DDC < VNUMDDC; DDC++)
            {
                while ((IQHeadPtr[DDC] - IQReadPtr[DDC]) > VIQBYTESPERFRAME)
                {
                    *(uint32_t*)UDPBuffer[DDC] = htonl(SequenceCounter[DDC]++);     // add sequence count
                    memset(UDPBuffer[DDC] + 4, 0, 8);                               // clear the timestamp data
                    *(uint16_t*)(UDPBuffer[DDC] + 12) = htons(24);                  // bits per sample
                    *(uint32_t*)(UDPBuffer[DDC] + 14) = htons(VIQSAMPLESPERFRAME);  // I/Q samples for ths frame
                    //
                    // now add I/Q data & send outgoing packet
                    //
                    memcpy(UDPBuffer[DDC] + 16, IQReadPtr[DDC], VIQBYTESPERFRAME);
                    IQReadPtr[DDC] += VIQBYTESPERFRAME;

                    int Error;
                    Error = sendmsg((ThreadData+DDC)->Socketid, &datagram, 0);

                    if (Error == -1)
                    {
                        printf("Send Error, DDC=%d, errno=%d, socket id = %d\n", DDC, errno, (ThreadData+DDC)->Socketid);
                        InitError = true;
                    }
                }
                //
                // now copy any residue to the start of the buffer (before the data copy in point)
                // unless the buffer already starts at or below the base
                // if we do a copy, the 1st free location is always base addr
                //
                ResidueBytes = IQHeadPtr[DDC] - IQReadPtr[DDC];
                //		printf("Residue = %d bytes\n",ResidueBytes);
                if (IQReadPtr[DDC] > IQBasePtr[DDC])                                // move data down
                {
                    if (ResidueBytes != 0) 		// if there is residue to move
                    {
                        memcpy(IQBasePtr[DDC] - ResidueBytes, IQReadPtr[DDC], ResidueBytes);
                        IQReadPtr[DDC] = IQBasePtr[DDC] - ResidueBytes;
                    }
                    else
                        IQReadPtr[DDC] = IQBasePtr[DDC];
                    IQHeadPtr[DDC] = IQBasePtr[DDC];                            // ready for new data at base
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
            Depth = ReadFIFOMonitorChannel(eRXDDCDMA, &FIFOOverflow);				// read the FIFO Depth register
            //		printf("read: depth = %d\n", Depth);
            while(Depth < (DMATransferSize/8))			// 8 bytes per location
            {
                usleep(1000);								// 1ms wait
                Depth = ReadFIFOMonitorChannel(eRXDDCDMA, &FIFOOverflow);				// read the FIFO Depth register
            //			printf("read: depth = %d\n", Depth);
            }
            //		printf("DMA read %d bytes from destination to base\n", VDMATRANSFERSIZE);
            DMAReadFromFPGA(IQReadfile_fd, DMAHeadPtr, DMATransferSize, VADDRDDCSTREAMREAD);
            DMAHeadPtr += DMATransferSize;
            EnoughData = true;

            //
            // finally copy data to DMA buffers according to the embedded DDC rate words
            // the 1st word is pointed by DMAReadPtr and it should point to a DDC rate word
            // (it should always be left in that state).
            // the top half of the 1st 64 bit word should be 0x8000
            // and that is located in the 2nd 32 bit location.
            // assume that DMA is > 1 frame.
            while (EnoughData)
            {
                LongWordPtr = (uint32_t*)DMAReadPtr;                                    // get 32 bit ptr
                RateWord = *LongWordPtr++;                                              // read rate word
                HdrWord = *LongWordPtr++;                                               // read rate flags
                if ((HdrWord & 0x80000000) == 0)                                        // if rate flag not set
                {
                    printf("Rate word not found when expected\n");
                    InitError = true;
                }
                else                                                                    // analyse word, then process
                {
                    if (RateWord != PrevRateWord)
                    {
                        FrameLength = AnalyseDDCHeader(RateWord, &DDCCounts);           // read new settings
                        PrevRateWord = RateWord;                                        // so so we know its analysed
                    }
                    if ((DMAHeadPtr - DMAReadPtr) >= (FrameLength * 8))                 // if enough bytes available
                    {
                        //THEN COPY DMA DATA TO I / Q BUFFERS
                        DMAReadPtr += 8;                                                // point to 1st location past rate word
                        SrcWordPtr = (uint16_t*)DMAReadPtr;                             // read sample data in 16 bit chunks
                        for (DDC = 0; DDC < VNUMDDC; DDC++)
                        {
                            HdrWord = DDCCounts[DDC];                                   // number of words for this DDC. reuse variable
                            if (HdrWord != 0)
                            {
                                DstWordPtr = (uint16_t *)IQHeadPtr[DDC];
                                for (Cntr = 0; Cntr < HdrWord; Cntr++)                  // count 64 bit words
                                {
                                    *DstWordPtr++ = *SrcWordPtr++;                      // move 48 bits of sample data
                                    *DstWordPtr++ = *SrcWordPtr++;
                                    *DstWordPtr++ = *SrcWordPtr++;
                                    SrcWordPtr++;                                       // and skip 16 bits where theres no data
                                }
                                IQHeadPtr[DDC] += 6 * HdrWord;                          // 6 bytes per sample
                            }
                            // read N samples; write at head ptr
                        }
                        DMAReadPtr += FrameLength * 8;                                  // that's how many bytes we read out
                    }
                    else
                        EnoughData = false;                                             // if not enough left, flag to read more
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
    free(DMAReadBuffer);
    //
    // free the per-DDC buffers
    //
    for (DDC = 0; DDC < VNUMDDC; DDC++)
    {
        free(UDPBuffer[DDC]);
        free(DDCSampleBuffer[DDC]);
    }

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
