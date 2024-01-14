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
#include "../common/version.h"



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
  ESoftwareID FPGASWID;                                 // preprod/release etc
  unsigned int FPGAVersion;                             // firmware version

  ThreadData = (struct ThreadSocketData *)arg;
  ThreadData->Active = true;
  printf("spinning up high priority incoming thread with port %d\n", ThreadData->Portid);
  FPGAVersion = GetFirmwareVersion(&FPGASWID);          // get version of FPGA code

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
      perror("recvfrom, high priority");
      printf("error number = %d\n", errno);
      return EXIT_FAILURE;
    }

    //
    // if correct packet, process it
    //
    if(size == VHIGHPRIOTIYTOSDRSIZE)
    {
      NewMessageReceived = true;
      LongWord = ntohl(*(uint32_t *)(UDPInBuffer));
      printf("high priority packet received, seq number = %d\n", LongWord);
      Byte = (uint8_t)(UDPInBuffer[4]);
      RunBit = (bool)(Byte&1);
      if(RunBit)
      {
        StartBitReceived = true;
        if(ReplyAddressSet && StartBitReceived)
        {
          SDRActive = true;                                       // only set active if we have replay address too
          SetTXEnable(true);
        }
      }
      else
      {
        SDRActive = false;                                       // set state of whole app
        SetTXEnable(false);
        EnableCW(false, false);
        printf("set to inactive by client app\n");
        StartBitReceived = false;
      }
      //
      // set TX or not TX
      //
      IsTXMode = (bool)(Byte&2);
      SetMOX(IsTXMode);

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
      printf("drive level = %d\n", Byte);
      SetTXDriveLevel(Byte);
      //
      // CAT port (if set)
      //
      Word = ntohs(*(uint16_t *)(UDPInBuffer+1398));
      printf("CAT over TCP port = %x\n", Word);

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
      // behaviour needs to be FPGA version specific: at V12, separate register added for Alex TX antennas
      // if new FPGA version: we write the word with TX ANT (byte 1428) to a new register, and the "old" word to original register
      // if we don't have a new TX ant bit set, just write "old" word data (byte 1432) to both registers
      // this is to allow safe operation with legacy client apps
      // 1st read bytes and see if a TX ant bit is set
      Word = ntohs(*(uint16_t *)(UDPInBuffer+1428));
      printf("Alex 1 TX word = 0x%x\n", Word);
      Word = (Word >> 8) & 0x0007;                          // new data TX ant bits. if not set, must be legacy client app
      
      if((FPGAVersion >= 12) && (Word != 0))                // if new firmware && client app supports it
      {
        //printf("new FPGA code, new client data\n");
        Word = ntohs(*(uint16_t *)(UDPInBuffer+1428));      // copy word with TX ant settings to filt/TXant register
        AlexManualTXFilters(Word, true);
        Word = ntohs(*(uint16_t *)(UDPInBuffer+1432));      // copy word with RX ant settings to filt/RXant register
        printf("Alex 0 TX word = 0x%x\n", Word);
        AlexManualTXFilters(Word, false);
      }
      else if(FPGAVersion >= 12)                            // new hardware but no client app support
      {
        //printf("new FPGA code, new client data\n");
        Word = ntohs(*(uint16_t *)(UDPInBuffer+1432));      // copy word with TX/RX ant settings to both registers
        AlexManualTXFilters(Word, true);
        AlexManualTXFilters(Word, false);
      }
      else                                                  // old FPGA hardware
      {
        //printf("old FPGA code\n");
        Word = ntohs(*(uint16_t *)(UDPInBuffer+1432));      // copy word with TX/RX ant settings to original register
        AlexManualTXFilters(Word, false);
      }
      // RX filters
      Word = ntohs(*(uint16_t *)(UDPInBuffer+1430));
      AlexManualRXFilters(Word, 2);
      printf("Alex 1 RX word = 0x%x\n", Word);
      Word = ntohs(*(uint16_t *)(UDPInBuffer+1434));
      AlexManualRXFilters(Word, 0);
      printf("Alex 0 RX word = 0x%x\n", Word);
      //
      // RX atten during TX and RX
      // this should be just on RX now, because TX settings are in the DUC specific packet bytes 58&59
      //
      Byte2 = (uint8_t)(UDPInBuffer[1442]);     // RX2 atten
      Byte = (uint8_t)(UDPInBuffer[1443]);      // RX1 atten
      SetADCAttenuator(eADC1, Byte, true, false);
      SetADCAttenuator(eADC2, Byte2, true, false);
      //
      // CWX bits
      //
      Byte = (uint8_t)(UDPInBuffer[5]);      // CWX
      SetCWXBits((bool)(Byte & 1), (bool)((Byte>>2) & 1), (bool)((Byte>>1) & 1));    // enabled, dash, dot
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



