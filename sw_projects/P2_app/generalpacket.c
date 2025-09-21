/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// generalpacket.c:
//
// handle "general packet to SDR" message
//
//////////////////////////////////////////////////////////////


#include "threaddata.h"
#include <stddef.h>
#include <stdio.h>
#include "generalpacket.h"
#include "../common/saturnregisters.h"
#include "../common/byteio.h"
#include "Outwideband.h"


bool HW_Timer_Enable = true;
uint8_t WidebandEnables;
uint16_t WidebandSampleCount;
uint8_t WidebandSampleSize;
uint8_t WidebandUpdateRate;
uint8_t WidebandPacketsPerFrame;


//
// protocol 2 handler for General Packet to SDR
// parameter is a pointer to the UDP message buffer.
// copy port numbers to port table, 
// then create listener threads for incoming packets & senders foroutgoing
//
int HandleGeneralPacket(uint8_t *PacketBuffer)
{
  uint16_t Port;                                  // port number from table
  int i;
  uint8_t Byte;

  SetPort(VPORTDDCSPECIFIC, rd_be_u16(PacketBuffer+5));
  SetPort(VPORTDUCSPECIFIC, rd_be_u16(PacketBuffer+7));
  SetPort(VPORTHIGHPRIORITYTOSDR, rd_be_u16(PacketBuffer+9));
  SetPort(VPORTSPKRAUDIO, rd_be_u16(PacketBuffer+13));
  SetPort(VPORTDUCIQ, rd_be_u16(PacketBuffer+15));
  SetPort(VPORTHIGHPRIORITYFROMSDR, rd_be_u16(PacketBuffer+11));
  SetPort(VPORTMICAUDIO, rd_be_u16(PacketBuffer+19));

// DDC ports start at the transferred value then increment
  Port = rd_be_u16(PacketBuffer+17);            // DDC0
  for (i=0; i<10; i++)
  {
    if(Port==0)
      SetPort(VPORTDDCIQ0+i, 0);
    else
      SetPort(VPORTDDCIQ0+i, Port+i);
  }  

// similarly, wideband ports start at the transferred value then increment
  Port = rd_be_u16(PacketBuffer+21);            // Wideband0
  for (i=0; i<2; i++)
  {
    if(Port==0)
      SetPort(VPORTWIDEBAND0+i, 0);
    else
      SetPort(VPORTWIDEBAND0+i, Port+i);
  }  
//
// now set the other data carried by this packet
// wideband capture data:
//
  WidebandEnables = *(uint8_t*)(PacketBuffer+23);                // get wideband enables
  WidebandSampleCount = rd_be_u16(PacketBuffer+24);              // wideband sample count
  WidebandSampleSize = *(uint8_t*)(PacketBuffer+26);             // wideband sample size
  WidebandUpdateRate = *(uint8_t*)(PacketBuffer+27);             // wideband update rate
  WidebandPacketsPerFrame = *(uint8_t*)(PacketBuffer+28);        // wideband packets per frame
  SetWidebandParams(WidebandEnables, WidebandSampleCount, WidebandSampleSize, WidebandUpdateRate, WidebandPacketsPerFrame);

//
// envelope PWM data:
//
  Port = rd_be_u16(PacketBuffer+33);        // PWM min
  SetMinPWMWidth(Port);
  Port = rd_be_u16(PacketBuffer+35);        // PWM max
  SetMaxPWMWidth(Port);
//
// various bits
//
  Byte = *(uint8_t*)(PacketBuffer+37);                // flag bits
  EnableTimeStamp((bool)(Byte&1));
  EnableVITA49((bool)(Byte&2));
  SetFreqPhaseWord((bool)(Byte&8));

  Byte = *(uint8_t*)(PacketBuffer+38);                // enable timeout
  HW_Timer_Enable = ((bool)(Byte&1));
  
  Byte = *(uint8_t*)(PacketBuffer+58);                // flag bits
  SetPAEnabled((bool)(Byte&1));
  SetApolloEnabled((bool)(Byte&2));

  Byte = *(uint8_t*)(PacketBuffer+59);                // Alex enable bits
  SetAlexEnabled(Byte);

  return 0;
}

