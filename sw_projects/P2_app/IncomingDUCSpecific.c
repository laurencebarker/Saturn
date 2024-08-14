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
    ssize_t size;                                             // UDP datagram length

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
          perror("recvfrom, DUC specific");
          return EXIT_FAILURE;
      }
      if(size == VDUCSPECIFICSIZE)
      {
          NewMessageReceived = true;
          printf("DUC packet received\n");
          // iambic settings
          uint8_t IambicSpeed = get_uint8(UDPInBuffer, 9);                // keyer speed
          uint8_t IambicWeight = get_uint8(UDPInBuffer, 10);              // keyer weight
          uint8_t keyerBoolBits = get_uint8(UDPInBuffer, 5);              // keyer bool bits
          SetCWIambicKeyer(IambicSpeed, IambicWeight,
                           (bool) ((keyerBoolBits >> 2) & 1),
                           (bool) ((keyerBoolBits >> 5) & 1),
                           (bool) ((keyerBoolBits >> 6) & 1),
                           (bool) ((keyerBoolBits >> 3) & 1),
                           (bool) ((keyerBoolBits >> 7) & 1));
          // general CW settings
          bool cwSidetone = (bool) ((keyerBoolBits >> 4) & 1);
          SetCWSidetoneEnabled(cwSidetone);
          bool cwEnabled = (bool) ((keyerBoolBits >> 1) & 1);
          bool cwBreakin = (bool)((keyerBoolBits >> 7) & 1);
          EnableCW(cwEnabled, cwBreakin);   // CW enabled bit, breakin bit

          uint8_t SidetoneVolume = get_uint8(UDPInBuffer, 6); // keyer speed
          uint16_t SidetoneFreq = get_uint16(UDPInBuffer, 7); // get frequency
          SetCWSidetoneVol(SidetoneVolume);
          SetCWSidetoneFrequency(SidetoneFreq);
          
          uint8_t CWRFDelay = get_uint8(UDPInBuffer, 13); // delay before CW on
          uint16_t CWHangDelay = get_uint16(UDPInBuffer, 11); // delay before CW off
          SetCWPTTDelay(CWRFDelay);
          SetCWHangTime(CWHangDelay);
          uint8_t CWRampTime = get_uint8(UDPInBuffer, 17); // ramp transition time
          if(CWRampTime != 0)                                     // if ramp period supported by client app
          {
              uint32_t CWRampTime_us = 1000 * CWRampTime;
              InitialiseCWKeyerRamp(true, CWRampTime_us);         // create required ramp, P2
          }

          // mic and line in options
          uint8_t micLineOptionsByte = get_uint8(UDPInBuffer, 50); // mic/line options
          SetMicBoost((micLineOptionsByte >> 1) & 1);
          SetMicLineInput((bool)(micLineOptionsByte & 1));
          SetOrionMicOptions((bool)((micLineOptionsByte >> 3)&1), (bool)((micLineOptionsByte >> 4)&1), (bool)((~micLineOptionsByte >> 2)&1));
          SetBalancedMicInput((bool)((micLineOptionsByte >> 5)&1));
          uint8_t lineInByte = get_uint8(UDPInBuffer, 51);                   // line in gain
          SetCodecLineInGain(lineInByte);
          uint8_t adc2Byte = get_uint8(UDPInBuffer, 58);                     // ADC2 att on TX
          SetADCAttenuator(eADC2, adc2Byte, false, true);
          uint8_t adc1Byte = get_uint8(UDPInBuffer, 59);                     // ADC1 att on TX
          SetADCAttenuator(eADC1, adc1Byte, false, true);
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









