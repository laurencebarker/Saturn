/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// OutHighPriority.c:
//
// handle "outgoing high priority data" message
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
#include <pthread.h>
#include <syscall.h>
#include "../common/saturnregisters.h"
#include "../common/saturndrivers.h"
#include "../common/byteio.h"
#include "LDGATU.h"


uint8_t GlobalFIFOOverflows = 0;             // FIFO overflow words



// this runs as its own thread to send outgoing data
// thread initiated after a "Start" command
// will be instructed to stop & exit by main loop setting enable_thread to 0
// this code signals thread terminated by setting active_thread = 0
//
void *OutgoingHighPriority(void *arg)
{
//
// variables for outgoing UDP frame
//
  struct iovec iovecinst;                                 // instance of iovec
  struct msghdr datagram;
  uint8_t UDPBuffer[VHIGHPRIOTIYFROMSDRSIZE];             // DDC frame buffer
  uint32_t SequenceCounter = 0;                           // UDP sequence count

  struct ThreadSocketData *ThreadData;            // socket etc data for this thread
  struct sockaddr_in DestAddr;                    // destination address for outgoing data
  bool InitError = false;
  int Error;
  uint8_t Byte;                                   // data being encoded
  uint16_t Word;                                  // data being encoded
  unsigned int FIFOCount;
  bool ATUTuneRequest = false;
  bool FIFOOverflow, FIFOUnderflow, FIFOOverThreshold;      // FIFO flags
  uint8_t FIFOOverflows;
  uint8_t ADCOverflows = 0;                       // set non zero if ADC overflows detected

//
// initialise. Create memory buffers and open DMA file devices
//
  ThreadData = (struct ThreadSocketData *)arg;
  ThreadData->Active = true;
  printf("spinning up outgoing high priority with port %d, pid=%ld\n", ThreadData->Portid, syscall(SYS_gettid));

//
// OK, now the main work
// thread commanded to transfer / stop transferring data by global bool SDRActive
// threat may also be commanded to close down and re-open its socket by command byte 
// VBITCHANGEPORT bit being set (shold only happen when not running)
//
  while (!InitError)
  {
    while(!(SDRActive))
    {
      if(ThreadData->Cmdid & VBITCHANGEPORT)
      {
        close(ThreadData->Socketid);                      // close old socket, open new one
        MakeSocket(ThreadData, 0);                        // this binds to the new port.
        ThreadData->Cmdid &= ~VBITCHANGEPORT;             // clear command bit
      }
      usleep(100);
    }
    //
    // if we get here, run has been initiated
    // initialise outgoing data packet
    //
    SequenceCounter = 0;
    printf("starting outgoing high priority data\n");
    memcpy(&DestAddr, &reply_addr, sizeof(struct sockaddr_in));           // local copy of PC destination address
    memset(&iovecinst, 0, sizeof(struct iovec));
    memset(&datagram, 0, sizeof(datagram));
    memset(UDPBuffer, 0,sizeof(UDPBuffer));                      // clear the whole packet
    iovecinst.iov_base = UDPBuffer;
    iovecinst.iov_len = VHIGHPRIOTIYFROMSDRSIZE;
    datagram.msg_iov = &iovecinst;
    datagram.msg_iovlen = 1;
    datagram.msg_name = &DestAddr;                   // MAC addr & port to send to
    datagram.msg_namelen = sizeof(DestAddr);

    //
    // this is the main loop. SDR is running. transfer data;
    // also check for changes to DDC enabled, and DDC interleaved
    //
    // potential race conditions: thread execution order is underfined. 
    // when a DDC becomes enabled, its paired DDC may not know yet and may still be set to interleaved.
    // when a DDC is set to interleaved, the paired DDC may not have been disabled yet.
    //
    while(SDRActive && !InitError)                               // main loop
    {
      uint16_t SleepCount;                                      // counter for sending next message
      uint8_t PTTBits;                                          // PTT bits - and change means a new message needed
      // create the packet
      *(uint32_t *)UDPBuffer = htonl(SequenceCounter++);        // add sequence count
      ReadStatusRegister();
      PTTBits = (uint8_t)GetP2PTTKeyInputs();
      *(uint8_t *)(UDPBuffer+4) = PTTBits;
      ADCOverflows |= (uint8_t)GetADCOverflow();                // add in any new overflows
      *(uint8_t *)(UDPBuffer+5) = ADCOverflows;
      ADCOverflows = 0;                                         // and clear ready for next test
      Word = (uint16_t)GetAnalogueIn(4);
      wr_be_u16(UDPBuffer+6, Word);                     // exciter power
      Word = (uint16_t)GetAnalogueIn(0);
      wr_be_u16(UDPBuffer+14, Word);                    // forward power
      Word = (uint16_t)GetAnalogueIn(1);
      wr_be_u16(UDPBuffer+22, Word);                    // reverse power
      Word = (uint16_t)GetAnalogueIn(5);
      wr_be_u16(UDPBuffer+49, Word);                    // supply voltage

      Word = (uint16_t)GetAnalogueIn(2);
      wr_be_u16(UDPBuffer+57, Word);                    // AIN3 user_analog1
      Word = (uint16_t)GetAnalogueIn(3);
      wr_be_u16(UDPBuffer+55, Word);                    // AIN4 user_analog2

      Byte = (uint8_t)GetUserIOBits();                  // user I/O bits
      *(uint8_t *)(UDPBuffer+59) = Byte;

//
// protocol V4.3: send FIFO depths and error states
// we can read a snapshot now, but under or overflows could have happened at other times too
// and they are cleared by the data transfer reads of the monitor channel
//
      FIFOOverflows = 0;
      ReadFIFOMonitorChannel(eRXDDCDMA, &FIFOOverflow, &FIFOOverThreshold, &FIFOUnderflow, &FIFOCount);				// read the DDC FIFO Depth register
      wr_be_u16(UDPBuffer+31, FIFOCount);                       // DDC samples
      if(FIFOOverThreshold)
        FIFOOverflows |= 0b00000001;

      ReadFIFOMonitorChannel(eMicCodecDMA, &FIFOOverflow, &FIFOOverThreshold, &FIFOUnderflow, &FIFOCount);				// read the mic FIFO Depth register
      Word = Word*4;                                            // 4 samples per FIFO location
      wr_be_u16(UDPBuffer+33, FIFOCount);                       // mic samples
      if(FIFOOverThreshold)
        FIFOOverflows |= 0b00000010;

      ReadFIFOMonitorChannel(eTXDUCDMA, &FIFOOverflow, &FIFOOverThreshold, &FIFOUnderflow, &FIFOCount);				// read the DUC FIFO Depth register
      Word = (Word*4)/3;                                        // 4/3 samples per FIFO location
      wr_be_u16(UDPBuffer+35, FIFOCount);                       // DUC samples
      if(FIFOUnderflow)
        FIFOOverflows |= 0b00000100;

      ReadFIFOMonitorChannel(eSpkCodecDMA, &FIFOOverflow, &FIFOOverThreshold, &FIFOUnderflow, &FIFOCount);				// read the speaker FIFO Depth register
      Word = Word*2;                                            // 2 samples per FIFO location
      wr_be_u16(UDPBuffer+37, FIFOCount);                       // speaker samples
      if(FIFOUnderflow)
        FIFOOverflows |= 0b00001000;

      FIFOOverflows |= GlobalFIFOOverflows;                   // copy in any bits set during normal data transfer
      *(uint8_t *)(UDPBuffer+30) = FIFOOverflows;
      GlobalFIFOOverflows = 0;                                // clear any overflows
      FIFOOverflows = 0;
      Error = sendmsg(ThreadData -> Socketid, &datagram, 0);


      //
      // get ATU bit and offer to LDG ATU handler
      // power requested if bit 2 is zero
      Byte = ((Byte >> 2) & 1) ^1;
      ATUTuneRequest = (bool)Byte;
      RequestATUTune(ATUTuneRequest);

      if(Error == -1)
      {
        printf("High Priority Send Error, errno=%d\n", errno);
        printf("socket id = %d\n", ThreadData -> Socketid);
        InitError=true;
      }
      //
      // now we need to sleep for 1ms (in TX) or 200ms (not in TX)
      // BUT if any of the PTT or key inputs change, or ADC overflow detected, send a message immediately
      // so break up the 200ms period with smaller sleeps
      // thank you to Rick N1GP for recommending this approach
      //
      SleepCount = (MOXAsserted) ? 2 : 400;
      while (SleepCount-- > 0)
      {
        ReadStatusRegister();
        if ((uint8_t)GetP2PTTKeyInputs() != PTTBits)
          break;
        ADCOverflows |= (uint8_t)GetADCOverflow();
        if(ADCOverflows != 0)
          break;
        usleep(500);
      }
    }
  }
//
// tidy shutdown of the thread
//
  if(InitError)                                           // if error, flag it to main program
    ThreadError = true;
  printf("shutting down outgoing high priority thread\n");
  close(ThreadData->Socketid); 
  ThreadData->Active = false;                   // signal closed
  return NULL;
}

