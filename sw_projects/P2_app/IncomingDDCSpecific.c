/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// incomingDDCspecific.c:
//
// handle handle "DDC specific" message
//
//////////////////////////////////////////////////////////////


#include "threaddata.h"
#include <stdint.h>
#include "../common/saturntypes.h"
#include "IncomingDDCSpecific.h"
#include <errno.h>
#include <stdlib.h>
#include <stddef.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include "../common/saturnregisters.h"




//
// listener thread for incoming DDC specific packets
//
void *IncomingDDCSpecific(void *arg)                    // listener thread
{
  struct ThreadSocketData *ThreadData;                  // socket etc data for this thread
  struct sockaddr_in addr_from;                         // holds MAC address of source of incoming messages
  uint8_t UDPInBuffer[VDDCSPECIFICSIZE];                // incoming buffer
  struct iovec iovecinst;                               // iovcnt buffer - 1 for each outgoing buffer
  struct msghdr datagram;                               // multiple incoming message header
  int size;                                             // UDP datagram length
  uint8_t Byte1, Byte2;                                 // received data
  bool Dither, Random;                                  // ADC bits
  uint16_t Word;                                        // 16 bit read value
  int i;                                                // counter
  EADCSelect ADC = eADC1;                               // ADC to use for a DDC

  ThreadData = (struct ThreadSocketData *)arg;
  ThreadData->Active = true;
  printf("spinning up DDC specific thread with port %d\n", ThreadData->Portid);
  //
  // main processing loop
  //
  while(1)
  {
    memset(&iovecinst, 0, sizeof(struct iovec));
    memset(&datagram, 0, sizeof(datagram));
    iovecinst.iov_base = &UDPInBuffer;                  // set buffer for incoming message number i
    iovecinst.iov_len = VDDCSPECIFICSIZE;
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
    if(size == VDDCSPECIFICSIZE)
    {
      printf("DDC specific packet received\n");
      // get ADC details:
      Byte1 = *(uint8_t*)(UDPInBuffer+4);                 // get ADC count
      SetADCCount(Byte1);
      Byte1 = *(uint8_t*)(UDPInBuffer+5);                 // get ADC Dither bits
      Byte2 = *(uint8_t*)(UDPInBuffer+6);                 // get ADC Random bits
      Dither  = (bool)(Byte1&1);
      Random  = (bool)(Byte2&1);
      SetADCOptions(eADC1, false, Dither, Random);        // ADC1 settings
      Byte1 = Byte1 >> 1;                                 // move onto ADC bits
      Byte2 = Byte2 >> 1;
      Dither  = (bool)(Byte1&1);
      Random  = (bool)(Byte2&1);
      SetADCOptions(eADC2, false, Dither, Random);        // ADC2 settings
      
      // get DDC settings
      Word = *(uint16_t*)(UDPInBuffer+7);                 // get DDC enables 15:0 (note low byte 1st!)
      for(i=0; i<VNUMDDC; i++)
      {
        HandlerSetDDCEnabled(i, (bool)(Word&1));          // bit=1 for DDC enabled
        Word = Word >> 1;                                 // move onto next DDC bit
      }

      // main settings for each DDC
      for(i=0; i<VNUMDDC; i++)
      {
        Byte1 = *(uint8_t*)(UDPInBuffer+i*6+17);          // get ADC for this DDC
        Word = *(uint16_t*)(UDPInBuffer+i*6+18);          // get sample rate for this DDC
        Byte2 = *(uint8_t*)(UDPInBuffer+i*6+22);          // get sample size for this DDC
        HandlerSetP2SampleRate(i, Word);
        SetDDCSampleSize(i, Byte2);
        if(Byte1 == 0)
          ADC = eADC1;
        else if(Byte1 == 1)
          ADC = eADC2;
        else if(Byte1 == 2)
          ADC = eTXSamples;
        SetDDCADC(i, ADC);
      }

      // finally DDC synchronisation
      // my implementation it seems isn't what the spec intended!
      // check: is DDC1 programmed to sync with DDC0;
      // check: is DDC3 programmed to sync with DDC2;
      // check: is DDC5 programmed to sync with DDC4;
      // check: is DDC7 programmed to sync with DDC6;
      // (reuse the Dither word)
      Dither = false;                                 // assume no synch
      Byte1 = *(uint8_t*)(UDPInBuffer+1363);          // get DDC0 synch
      if(Byte1 == 0b00000010)
        Dither = true;
      HandlerSetDDCInterleaved(1, Dither);

      Dither = false;                                 // assume no synch
      Byte1 = *(uint8_t*)(UDPInBuffer+1365);          // get DDC2 synch
      if(Byte1 == 0b00001000)
        Dither = true;
      HandlerSetDDCInterleaved(3, Dither);

      Dither = false;                                 // assume no synch
      Byte1 = *(uint8_t*)(UDPInBuffer+1367);          // get DDC4 synch
      if(Byte1 == 0b00100000)
        Dither = true;
      HandlerSetDDCInterleaved(5, Dither);

      Dither = false;                                 // assume no synch
      Byte1 = *(uint8_t*)(UDPInBuffer+1369);          // get DDC6 synch
      if(Byte1 == 0b10000000)
        Dither = true;
      HandlerSetDDCInterleaved(7, Dither);



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






