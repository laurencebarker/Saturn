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
// OutHighPriority.c:
//
// handle "outgoing high priority data" message
//
//////////////////////////////////////////////////////////////

#include "threaddata.h"
#include <stdint.h>
#include "saturntypes.h"
#include "OutHighPriority.h"
#include <errno.h>
#include <stdlib.h>
#include <stddef.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>




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

//
// initialise. Create memory buffers and open DMA file devices
//
  ThreadData = (struct ThreadSocketData *)arg;
  ThreadData->Active = true;
  printf("spinning up outgoing high priority with port %d\n", ThreadData->Portid);

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

    while(SDRActive && !InitError)                               // main loop
    {
      // create the packet
      *(uint32_t *)UDPBuffer = htonl(SequenceCounter++);        // add sequence count
      Byte = (uint8_t)GetP2PTTKeyInputs();
      *(uint8_t *)(UDPBuffer+4) = Byte;
      Byte = (uint8_t)GetADCOverflow();
      *(uint8_t *)(UDPBuffer+5) = Byte;
      Word = (uint16_t)GetAnalogueIn(4);
      *(uint16_t *)(UDPBuffer+6) = Word;                // exciter power
      Word = (uint16_t)GetAnalogueIn(0);
      *(uint16_t *)(UDPBuffer+14) = Word;               // forward power
      Word = (uint16_t)GetAnalogueIn(1);
      *(uint16_t *)(UDPBuffer+22) = Word;               // reverse power
      Word = (uint16_t)GetAnalogueIn(5);
      *(uint16_t *)(UDPBuffer+49) = Word;               // supply voltage

      Word = (uint16_t)GetAnalogueIn(2);
      *(uint16_t *)(UDPBuffer+53) = Word;               // AIN3
      Word = (uint16_t)GetAnalogueIn(3);
      *(uint16_t *)(UDPBuffer+51) = Word;               // AIN4

      Byte = (uint8_t)GetUserIOBits();                  // user I/O bits
      *(uint8_t *)(UDPBuffer+59) = Byte;

      Error = sendmsg(ThreadData -> Socketid, &datagram, 0);

      if(Error == -1)
      {
        printf("High Priority Send Error, errno=%d\n", errno);
        printf("socket id = %d\n", ThreadData -> Socketid);
        InitError=true;
      }
      usleep(50000);                                    // 50ms gap between messages
    }
  }
//
// tidy shutdown of the thread
//
  printf("shutting down outgoing mic thread\n");
  close(ThreadData->Socketid); 
  ThreadData->Active = false;                   // signal closed
  return NULL;
}

