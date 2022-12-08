/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// InHighPriority.c:
//
// handle "incoming high priority" message
//
//////////////////////////////////////////////////////////////

#include "threaddata.h"
#include <stdint.h>
#include "../common/saturntypes.h"
#include "InHighPriority.h"
#include <errno.h>
#include <stdlib.h>
#include <stddef.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include "../common/saturnregisters.h"
#include "../common/hwaccess.h"                   // low level access



//
// listener thread for incoming high priority packets
//
void *IncomingHighPriority(void *arg)                   // listener thread
{
  struct ThreadSocketData *ThreadData;                  // socket etc data for this thread
  struct sockaddr_in addr_from;                         // holds MAC address of source of incoming messages
  uint8_t UDPInBuffer[VHIGHPRIOTIYTOSDRSIZE];           // incoming buffer
  struct iovec iovecinst;                               // iovcnt buffer - 1 for each outgoing buffer
  struct msghdr datagram;                               // multiple incoming message header
  int size;                                             // UDP datagram length
  bool RunBit;                                          // true if "run" bit set
  uint32_t DDCPhaseIncrement;                           // delta phase for a DDC
  uint8_t Byte, Byte2;                                  // received dat being decoded
  uint32_t LongWord;
  uint16_t Word;
  int i;                                                // counter

  ThreadData = (struct ThreadSocketData *)arg;
  ThreadData->Active = true;
  printf("spinning up high priority incoming thread with port %d\n", ThreadData->Portid);

  //
  // main processing loop
  //
  while(1)
  {
    memset(&iovecinst, 0, sizeof(struct iovec));
    memset(&datagram, 0, sizeof(datagram));
    iovecinst.iov_base = &UDPInBuffer;                  // set buffer for incoming message number i
    iovecinst.iov_len = VHIGHPRIOTIYTOSDRSIZE;
    datagram.msg_iov = &iovecinst;
    datagram.msg_iovlen = 1;
    datagram.msg_name = &addr_from;
    datagram.msg_namelen = sizeof(addr_from);
    size = recvmsg(ThreadData->Socketid, &datagram, 0);         // get one message. If it times out, ges size=-1
    if(size < 0 && errno != EAGAIN)
    {
      perror("recvfrom");
      return EXIT_FAILURE;
    }

    //
    // if correct packet, process it
    //
    if(size == VHIGHPRIOTIYTOSDRSIZE)
    {
      printf("high priority packet received\n");
      Byte = (uint8_t)(UDPInBuffer[4]);
      RunBit = (bool)(Byte&1);
      SDRActive = RunBit;                                       // set state of whole app
      IsTXMode = (bool)(Byte&2);
      SetMOX(IsTXMode);

      //
      // Saturn current test code - to be removed eventually
      // get DDC0 and DDC2 phase word and send to FPGA
//      DDCPhaseIncrement = ntohl(*(uint32_t *)(UDPInBuffer+9));
//      printf("DDC0 delta phi = %d\n", DDCPhaseIncrement);
//      RegisterWrite(0x0000, DDCPhaseIncrement);                 // short term bodge!
//      DDCPhaseIncrement = ntohl(*(uint32_t *)(UDPInBuffer+17));
//      printf("DDC2 delta phi = %d\n", DDCPhaseIncrement);
//      RegisterWrite(0x0008, DDCPhaseIncrement);                 // short term bodge!
//      SetDDCFrequency(0, DDCPhaseIncrement, true);
//
// now properly decode DDC frequencies
//
      for (i=0; i<VNUMDDC; i++)
      {
        LongWord = ntohl(*(uint32_t *)(UDPInBuffer+i*4+9));
        SetDDCFrequency(i, LongWord, true);                   // temporarily set above
      }
      //
      // DUC frequency & drive level
      //
      LongWord = ntohl(*(uint32_t *)(UDPInBuffer+329));
      SetDUCFrequency(LongWord, true);
      Byte = (uint8_t)(UDPInBuffer[345]);
      SetTXDriveLevel(Byte);
      //
      // transverter, speaker mute, open collector, user outputs
      //
      Byte = (uint8_t)(UDPInBuffer[1400]);
      SetXvtrEnable((bool)(Byte&1));
      SetSpkrMute((bool)((Byte>>1)&1));
      Byte = (uint8_t)(UDPInBuffer[1401]);
      SetOpenCollectorOutputs(Byte);
      Byte = (uint8_t)(UDPInBuffer[1402]);
      SetUserOutputBits(Byte);
      //
      // Alex
      //
      Word = ntohs(*(uint16_t *)(UDPInBuffer+1430));
      AlexManualRXFilters(Word, 2);
      Word = ntohs(*(uint16_t *)(UDPInBuffer+1432));
      AlexManualTXFilters(Word);
      Word = ntohs(*(uint16_t *)(UDPInBuffer+1434));
      AlexManualRXFilters(Word, 0);
      //
      // RX atten during TX
      //
      Byte2 = (uint8_t)(UDPInBuffer[1442]);
      Byte = (uint8_t)(UDPInBuffer[1443]);
      SetADCAttenDuringTX(Byte, Byte2);
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



