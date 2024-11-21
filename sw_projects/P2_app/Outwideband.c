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

#define VWBPACKETSIZE 1500                          // packet size is a variable, sp make max for UDP
#define VWBSAMPLESPERFRAME 512                      // total wideband ADC samples in one WB packet
#define VWBBYTESPERFRAME 2*VWBSAMPLESPERFRAME       // total bytes in one outgoing frame
#define VSTARTUPDELAY 100                           // 100 messages (~100ms) before reporting under or overflows
#define VNUMWBADC 2                                 // number of ADC that WB data can be collected for


//
// define the memory buffers:
//
uint8_t* WBDMAReadBuffer = NULL;								// data for DMA read from DDC
uint32_t WBDMABufferSize = VDMABUFFERSIZE;

uint8_t* WBUDPBuffer[VNUMDDC];                                  // DDC frame buffer
extern  int DMAReadfile_fd;								        // DMA read file device (opened by mic samples thread)

//
// copies of params provided by P2 protocol
// WBParamsChanged set true if parameters have moved
//
bool WBParamsChanged;
uint8_t StoredEnables;                                          // enable bits for ADC1 (bit0) & 2 (bit1)
uint16_t StoredSamplePerPktCount;                               // samples per packet count
uint8_t StoredSampleSize;                                       // sample resolution in bits (typ 16)
uint8_t StoredRate;                                             // update rate in ms
uint8_t StoredPacketCount;                                      // packets to be transferred out



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
// see if any differences are present, then store for when thread is ready
//
void SetWidebandParams(uint8_t Enables, uint16_t SampleCount, uint8_t SampleSize, uint8_t Rate, uint8_t PacketCount)
{
    if((Enables != StoredEnables) || (SampleCount != StoredSamplePerPktCount) || (SampleSize != StoredSampleSize)
       || (Rate != StoredRate) || (PacketCount != StoredPacketCount))
        WBParamsChanged = true;

    StoredEnables = Enables;                            // enable bits for ADC1 (bit0) & 2 (bit1)
    StoredSamplePerPktCount = SampleCount;                    // samples per packet count
    StoredSampleSize = SampleSize;                      // sample resolution in bits (typ 16)
    StoredRate = Rate;                                  // update rate in ms
    StoredPacketCount = PacketCount;                    // packets to be transferred out

    if(WBParamsChanged)
        printf("New WB data: Enables=%d, Sample/pkt = %d, Samplesize=%d, Rate=%d, PktCount=%d\n", Enables, SampleCount, SampleSize, Rate, PacketCount);
}


//
// read out the Wideband FIFO
// returns the number of samples read
// read available word count, then do DMA to memory buffer
//
uint32_t ReadFIFOContent()
{
    uint32_t SampleCount = 0;
    uint32_t WordCount = 0;                             // count of 64 bit words in the FIFO
    bool ADC1, ADC2;

    WordCount = GetWidebandStatus(&ADC1, &ADC2);
    if(WordCount != 0)
    {
        sem_wait(&MicWBDMAMutex);                       // get protected access
        DMAReadFromFPGA(DMAReadfile_fd, WBDMAReadBuffer, WordCount * 8, VADDRWIDEBANDREAD);
        sem_post(&MicWBDMAMutex);                       // get protected access
        SampleCount = WordCount * 4;
//        printf("word count in readFIFOContent = %d\n", WordCount);
    }
    return SampleCount;
}


//
// strategy:
// 1. We have one DMA buffer, big enough for the largest DMA from the wideband FIFO
// 2. On startup: turn off the IP and clear the FIFO if any data in it. 
// 3. when the wideband settings change: stop operation; clear FIFO; setup new settings & restart if still enabled
// 4. wideband IP started; it periodically writes defined sample count to FIFO
// 5. When write complete, a status flag is set; one for each ADC
// 6. when a flag is set, DMA out the data for that ADC then write the bit to say "data transferred"
// 7. break data into N outgoing packets and send to Thetis over UDP
// 8. Need to check if both ADCs are enabled, because more data will follow if so
// 9. when exiting: turn off the IP.
//


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
    uint32_t SampleWordCount;                                   // no of 64 bit words required
    bool ADC1, ADC2;                                            // true if data available
    uint32_t PacketCounter;
    uint32_t StartAddress;                                      // data locations in wideband collected data
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
// (strategy step 1)
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
// (strategy step 2)
// 
    SetWidebandEnable(false, false, false);                 // turn off data collection
    usleep(150);                                            // wait dfor any current write to end
    ReadFIFOContent();                                      // then empty the FIFO

//
// thread loop. runs continuously until commanded by main loop to exit
// initialise thread data structures;
// then while there is wideband data, make outgoing packets;
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
        // initialise outgoing WB packet buffers - 1 per ADC
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
            datagram[ADC].msg_namelen = sizeof(struct sockaddr_in);
        }
      //
      // enable Saturn WB IP to transfer data
      // this is the main app loop
      // monitor changes to paramters, because this is the trigger to reconfigure operation
      //
        printf("outDDCIQ: enable data transfer\n");
        while(!InitError && SDRActive)
        {
//
// if parameters have changed, halt then re-load configuration (strategy step 3)
// (this will also work from a cold start)
//
            if(WBParamsChanged)
            {
                SetWidebandEnable(false, false, false);                 // turn off data collection
                usleep(150);                                            // wait for any current write to end
                ReadFIFOContent();                                      // then empty the FIFO discarding data
                SampleWordCount = ((StoredSamplePerPktCount * StoredPacketCount) / 4) + 8;    // no. 64 bit words; over-read by 8 words
                SetWidebandSampleCount(SampleWordCount);
                SetWidebandUpdateRate(StoredRate);
                SetWidebandEnable((bool)(StoredEnables&1), (bool)(StoredEnables&2), false);
                printf("Setting WB IP: WordCount = %d, Rate = %d, ADC1 = %d, ADC2=%d\n", SampleWordCount, StoredRate, (StoredEnables&1), (StoredEnables&2));
                WBParamsChanged = false;
            }
//
// then if enabled:
// using a while loop, wait for data to be available from the FPGA. 
// When it is, read it and clear the IP "data available" flag
// (strategy step 6)
// then send out packets to SDR client
// recheck if parameters have changed after a successful ready
//
            if(StoredEnables != 0)                      // if active
            {
                GetWidebandStatus(&ADC1, &ADC2);      // get flags for data available
                if(ADC1 || ADC2)                                        // if data available for either
                {
                    SampleWordCount = ReadFIFOContent();                // then read FIFO till empty
//                    printf("WB data available, ADC sample count = %d\n", SampleWordCount);
                    SetWidebandEnable((bool)(StoredEnables&1), (bool)(StoredEnables&2), true);  // re-enable record
                    //
                    // now transfer data out on UDP packets
                    // first select the buffer set yo use based on what data is available
                    //
                    if(ADC2)
                        ADC=1;
                    else
                        ADC=0;
                    SequenceCounter[ADC] = 0;                           // restart at 0 for each frame
                    for(PacketCounter = 0; PacketCounter < StoredPacketCount; PacketCounter++)
                    {
                        *(uint32_t*)WBUDPBuffer[ADC] = htonl(SequenceCounter[ADC]++);     // add sequence count
                        //
                        // now add I/Q data & send outgoing packet
                        //
                        StartAddress = (PacketCounter * StoredSamplePerPktCount * 2) + 32;   // byte address; inset 4 words into recording
                        memcpy(WBUDPBuffer[ADC] + 4, WBDMAReadBuffer + StartAddress, StoredSamplePerPktCount * 2);
                        iovecinst[ADC].iov_len = StoredSamplePerPktCount * 2 + 4;           // P2 data dependent

                        int Error;
                        Error = sendmsg((ThreadData+ADC)->Socketid, &datagram[ADC], 0);
                        usleep(200);                    // gap between outgoing messages
                    }
                }
            }
            usleep(5000);

        }     // end of while(!InitError&& SDRActive) loop - typically when comm with SDR client stops
        StoredEnables = false;                                          // force a re-config if comm continues later
    } //end of while(!InitError)

//
// tidy shutdown of the thread
// halt the wideband IP (strategy step 9)
//
    printf("shutting down Wideband outgoing thread\n");
    SetWidebandEnable(false, false, false);
    close(ThreadData->Socketid); 
    ThreadData->Active = false;                   // signal closed
    FreeWBDynamicMemory();
    return NULL;
}