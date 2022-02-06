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
// OutMicAudio.c:
//
// handle "outgoing microphone audio" message
//
//////////////////////////////////////////////////////////////

#include "threaddata.h"
#include <stdint.h>
#include "saturntypes.h"
#include "OutMicAudio.h"
#include <errno.h>
#include <stdlib.h>
#include <stddef.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>


#define VMICSAMPLESPERFRAME 64




// temp variable for getting mic sample rate correct
extern uint32_t TransferredIQSamples;






// this runs as its own thread to send outgoing data
// thread initiated after a "Start" command
// will be instructed to stop & exit by main loop setting enable_thread to 0
// this code signals thread terminated by setting active_thread = 0
// for now this code aims to send out packets until it is just ahead of the I/Q packets
//
void *OutgoingMicSamples(void *arg)
{
  uint32_t TransferredMicSamples=0;
//
// variables for outgoing UDP frame
//
  struct iovec iovecinst;                                 // instance of iovec
  struct msghdr datagram;
  uint8_t UDPBuffer[VMICPACKETSIZE];                      // DDC frame buffer
  uint32_t SequenceCounter = 0;                           // UDP sequence count

  struct ThreadSocketData *ThreadData;            // socket etc data for this thread
  struct sockaddr_in DestAddr;                    // destination address for outgoing data
  bool InitError = false;
  int Error;

//
// initialise. Create memory buffers and open DMA file devices
//
  ThreadData = (struct ThreadSocketData *)arg;
  ThreadData->Active = true;
  printf("spinning up outgoing mic thread with port %d\n", ThreadData->Portid);


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
    memcpy(&DestAddr, &reply_addr, sizeof(struct sockaddr_in));           // local copy of PC destination address
    memset(&iovecinst, 0, sizeof(struct iovec));
    memset(&datagram, 0, sizeof(datagram));
    iovecinst.iov_base = UDPBuffer;
    iovecinst.iov_len = VMICPACKETSIZE;
    datagram.msg_iov = &iovecinst;
    datagram.msg_iovlen = 1;
    datagram.msg_name = &DestAddr;                   // MAC addr & port to send to
    datagram.msg_namelen = sizeof(DestAddr);

    while(SDRActive && !InitError)                               // main loop
    {
      // create the packet into UDPBuffer
      if(TransferredIQSamples >= TransferredMicSamples)         // if mic samples is caught up, just sleep for 1ms then try again
      {
        // send a dummy mic packet with zero data
        memset(UDPBuffer, 0,sizeof(UDPBuffer));                      // clear the whole packet
        *(uint32_t *)UDPBuffer = htonl(SequenceCounter++);        // add sequence count
        Error = sendmsg(ThreadData -> Socketid, &datagram, 0);
        TransferredMicSamples += VMICSAMPLESPERFRAME;
      }
      else
        usleep(1000);
      if(Error == -1)
      {
        printf("Mic Send Error, errno=%d\n", errno);
        printf("socket id = %d\n", ThreadData -> Socketid);
        InitError=true;
      }
    }
  }
//
// tidy shutdown of the thread
//
  printf("shutting down outgoing mic data thread\n");
  close(ThreadData->Socketid); 
  ThreadData->Active = false;                   // signal closed
  return NULL;
}
