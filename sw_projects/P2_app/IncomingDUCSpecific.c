/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// incomingDUCspecific.c:
//
// handle handle "DUC specific" message
// (also shown as "TX specific" in the protocol document)
//
//////////////////////////////////////////////////////////////


#include "threaddata.h"
#include <stdint.h>
#include "../common/saturntypes.h"
#include "IncomingDUCSpecific.h"
#include <errno.h>
#include <stdlib.h>
#include <stddef.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include "../common/saturnregisters.h"



//
// listener thread for incoming DUC specific packets
//
void *IncomingDUCSpecific(void *arg)                    // listener thread
{ 
    struct ThreadSocketData *ThreadData;                  // socket etc data for this thread
    struct sockaddr_in addr_from;                         // holds MAC address of source of incoming messages
    uint8_t UDPInBuffer[VDUCSPECIFICSIZE];                // incoming buffer
    struct iovec iovecinst;                               // iovcnt buffer - 1 for each outgoing buffer
    struct msghdr datagram;                               // multiple incoming message header
    int size;                                             // UDP datagram length
    uint8_t Byte;
    uint16_t SidetoneFreq;                                // freq for audio sidetone
    uint8_t IambicSpeed;                                  // WPM
    uint8_t IambicWeight;                                 //
    uint8_t SidetoneVolume;
    uint8_t CWRFDelay;
    uint16_t CWHangDelay;

    ThreadData = (struct ThreadSocketData *)arg;
    ThreadData->Active = true;
    printf("spinning up DUC specific thread with port %d\n", ThreadData->Portid);
    //
    // main processing loop
    //
    while(1)
    {
      memset(&iovecinst, 0, sizeof(struct iovec));
      memset(&datagram, 0, sizeof(datagram));
      iovecinst.iov_base = &UDPInBuffer;                  // set buffer for incoming message number i
      iovecinst.iov_len = VDUCSPECIFICSIZE;
      datagram.msg_iov = &iovecinst;
      datagram.msg_iovlen = 1;
      datagram.msg_name = &addr_from;
      datagram.msg_namelen = sizeof(addr_from);
      size = recvmsg(ThreadData->Socketid, &datagram, 0);         // get one message. If it times out, ges size=-1
      if(size < 0 && errno != EAGAIN)
      {
          perror("recvfrom");
  //      return EXIT_FAILURE;
      }
      if(size == VDUCSPECIFICSIZE)
      {
          printf("DUC packet received\n");
// iambic settings
          IambicSpeed = *(uint8_t*)(UDPInBuffer+9);               // keyer speed
          IambicWeight = *(uint8_t*)(UDPInBuffer+10);             // keyer weight
          Byte = *(uint8_t*)(UDPInBuffer+5);                      // keyer bool bits
          SetCWIambicKeyer(IambicSpeed, IambicWeight, (bool)((Byte >> 2)&1), (bool)((Byte >> 5)&1), 
                          (bool)((Byte >> 6)&1), (bool)((Byte >> 3)&1), (bool)((Byte >> 7)&1));
// general CW settings
          SetCWSidetoneEnabled((bool)((Byte >> 4)&1));
          EnableCW((bool)((Byte >> 1)&1));                        // CW enabled bit
          SidetoneVolume = *(uint8_t*)(UDPInBuffer+6);            // keyer speed
          SidetoneFreq = *(uint16_t*)(UDPInBuffer+7);             // get frequency
          SidetoneFreq = ntohs(SidetoneFreq);                     // convert from big endian
          SetCWSidetoneVol(SidetoneVolume);
          SetCWSidetoneFrequency(SidetoneFreq);
          CWRFDelay = *(uint8_t*)(UDPInBuffer+13);                // delay before CW on
          CWHangDelay = *(uint16_t*)(UDPInBuffer+11);             // delay before CW off
          CWHangDelay = ntohs(CWHangDelay);                       // convert from big endian
          SetCWPTTDelay(CWRFDelay);
          SetCWHangTime(CWHangDelay);
// mic and line in options
          Byte = *(uint8_t*)(UDPInBuffer+50);                     // mic/line options
          SetMicBoost((bool)((Byte >> 1)&1));
          SetMicLineInput((bool)(Byte&1));
          SetOrionMicOptions((bool)((Byte >> 3)&1), (bool)((Byte >> 4)&1), (bool)((~Byte >> 2)&1));
          Byte = *(uint8_t*)(UDPInBuffer+51);                     // line in gain
          SetCodecLineInGain(Byte);
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









