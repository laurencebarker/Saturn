/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 1 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
// derived from Pavel Demin code 
//
// p2app.c:
//
// Protocol2 is defined by "openHPSDR Ethernet Protocol V3.8"
// unlike protocol 1, it uses multiple ports for the data endpoints
//
//////////////////////////////////////////////////////////////


#include <stdio.h>
#include <errno.h>
#include <stdlib.h>
#include <limits.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <math.h>
#include <pthread.h>
#include <termios.h>
#include <sys/time.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <net/if.h>

#include "hwaccess.h"                     // access to PCIe read & write
#include "saturnregisters.h"              // register I/O for Saturn


struct sockaddr_in reply_addr;              // destination address for outgoing data

int enable_thread = 0;                      // true if outgoing data thread enabled
int active_thread = 0;                      // true if outgoing thread is running

void *OutgoingDDCIQ(void *arg);
void *IncomingDDCSpecific(void *arg);           // listener thread
void *IncomingDUCSpecific(void *arg);           // listener thread
void *IncomingHighPriority(void *arg);          // listener thread
void *IncomingDUCIQ(void *arg);                 // listener thread
void *IncomingSpkrAudio(void *arg);             // listener thread


#define SDRBOARDID 1                    // Hermes
#define SDRSWVERSION 1                  // version of this software
#define VDDCPACKETSIZE 1444             // each DDC packet
#define VDISCOVERYREPLYSIZE 60          // reply packet
#define VDISCOVERYSIZE 60               // discovery packet
#define VHIGHPRIOTIYTOSDRSIZE 1444      // high priority packet to SDR
#define VSPEAKERAUDIOSIZE 260           // speaker audio packet
#define VDUCIQSIZE 1444                 // TX DUC I/Q data packet
#define VDDCSPECIFICSIZE 1444           // DDC specific packet
#define VDUCSPECIFICSIZE 60             // DUC specific packet

//
// list of port numbers, provided in the general packet
// (port 1024 for discovery and general packets not needed in this list)
#define VPORTTABLESIZE 20
// incoming port numbers
#define VPORTCOMMAND 0
#define VPORTDDCSPECIFIC 1
#define VPORTDUCSPECIFIC 2
#define VPORTHIGHPRIORITYTOSDR 3
#define VPORTSPKRAUDIO 4
#define VPORTDUCIQ 5
// outgoing port numbers:
#define VPORTHIGHPRIORITYFROMSDR 6
#define VPORTMICAUDIO 7
#define VPORTDDCIQ0 8
#define VPORTDDCIQ1 9
#define VPORTDDCIQ2 10
#define VPORTDDCIQ3 11
#define VPORTDDCIQ4 12
#define VPORTDDCIQ5 13
#define VPORTDDCIQ6 14
#define VPORTDDCIQ7 15
#define VPORTDDCIQ8 16
#define VPORTDDCIQ9 17
#define VPORTWIDEBAND0 18
#define VPORTWIDEBAND1 19


//
// a type to hold data for each incoming or outgoing data thread
//
struct ThreadSocketData
{
  uint32_t DDCid;                               // only relevant to DDC threads
  int Socketid;                                 // socket to access internet
  uint16_t Portid;                              // port to access
  char *Nameid;                                 // name (for error msg etc)
  bool Active;                                  // true if thread is active
  struct sockaddr_in addr_cmddata;
  uint32_t Cmdid;                               // command from app to thread - bits set for each command
};
#define VBITCHANGEPORT 1                        // if set, thread must close its socket and open a new one on different port
#define VBITDATARUN 2                           // if set, streaming threads stream data
#define VBITINTERLEAVE 4                        // if set, DDC threads should interleave data

struct ThreadSocketData SocketData[VPORTTABLESIZE] =
{
  {0, 0, 1024, "Cmd", false,{}, 0},                      // command (incoming) thread
  {0, 0, 1025, "DDC Specific", false,{}, 0},             // DDC specifc (incoming) thread
  {0, 0, 1026, "DUC Specific", false,{}, 0},             // DUC specific (incoming) thread
  {0, 0, 1027, "High Priority In", false,{}, 0},         // High Priority (incoming) thread
  {0, 0, 1028, "Spkr Audio", false,{}, 0},               // Speaker Audio (incoming) thread
  {0, 0, 1029, "DUC I/Q", false,{}, 0},                  // DUC IQ (incoming) thread
  {0, 0, 1025, "High Priority Out", false,{}, 0},        // High Priority (outgoing) thread
  {0, 0, 1026, "Mic Audio", false,{}, 0},                // Mic Audio (outgoing) thread
  {0, 0, 1035, "DDC I/Q 0", false,{}, 0},                // DDC IQ 0 (outgoing) thread
  {0, 0, 1036, "DDC I/Q 1", false,{}, 0},                // DDC IQ 1 (outgoing) thread
  {0, 0, 1037, "DDC I/Q 2", false,{}, 0},                // DDC IQ 2 (outgoing) thread
  {0, 0, 1038, "DDC I/Q 3", false,{}, 0},                // DDC IQ 3 (outgoing) thread
  {0, 0, 1039, "DDC I/Q 4", false,{}, 0},                // DDC IQ 4 (outgoing) thread
  {0, 0, 1040, "DDC I/Q 5", false,{}, 0},                // DDC IQ 5 (outgoing) thread
  {0, 0, 1041, "DDC I/Q 6", false,{}, 0},                // DDC IQ 6 (outgoing) thread
  {0, 0, 1042, "DDC I/Q 7", false,{}, 0},                // DDC IQ 7 (outgoing) thread
  {0, 0, 1043, "DDC I/Q 8", false,{}, 0},                // DDC IQ 8 (outgoing) thread
  {0, 0, 1044, "DDC I/Q 9", false,{}, 0},                // DDC IQ 9 (outgoing) thread
  {0, 0, 1027, "Wideband 0", false,{}, 0},               // Wideband 0 (outgoing) thread
  {0, 0, 1028, "Wideband 1", false,{}, 0}                // Wideband 1 (outgoing) thread
};


//
// default port numbers, used if incoming port number = 0
//
uint16_t DefaultPorts[VPORTTABLESIZE] =
{
  1024, 1025, 1026, 1027, 1028, 
  1029, 1025, 1026, 1035, 1036, 
  1037, 1038, 1039, 1040, 1041, 
  1042, 1043, 1044, 1027, 1028
};


pthread_t DDCSpecificThread;
pthread_t DUCSpecificThread;
pthread_t HighPriorityToSDRThread;
pthread_t SpkrAudioThread;
pthread_t DUCIQThread;
pthread_t DDCIQThread[VNUMDDC];               // array, but not sure how many



//
// function to check if any threads are still active
// lop through the table; report if any are true.
// parameter is to allow the "command" socket to stay open
//
bool CheckActiveThreads(int StartingPoint)
{
  struct ThreadSocketData* Ptr = SocketData+StartingPoint;
  bool Result = false;

  for (int i = StartingPoint; i < VPORTTABLESIZE; i++)          // loop through the socket table
  {
    if(Ptr->Active)                                 // check this thread
      Result = true;
    Ptr++;
  }
    if(Result)
      printf("found an active thread\n");
    return Result;
}



//
// set the port for a given thread. If 0, set the default according to HPSDR spec.
// if port is different from the currently assigned one, set the "change port" bit
//
void SetPort(uint32_t ThreadNum, uint16_t PortNum)
{
  uint16_t CurrentPort;

  CurrentPort = SocketData[ThreadNum].Portid;
  if(PortNum == 0)
    SocketData[ThreadNum].Portid = DefaultPorts[ThreadNum];     //default if not set
  else
    SocketData[ThreadNum].Portid = PortNum;

  if (SocketData[ThreadNum].Portid != CurrentPort)
    SocketData[ThreadNum].Cmdid |= VBITCHANGEPORT;
}



//
// function to make an incoming or outgoing socket, bound to the specified port in the structure
// 1st parameter is a link into the socket data table
//
int MakeSocket(struct ThreadSocketData* Ptr, int DDCid)
{
  struct timeval ReadTimeout;                                       // read timeout
  int yes = 1;
//  struct sockaddr_in addr_cmddata;
  //
  // create socket for incoming data
  //
  if((Ptr->Socketid = socket(AF_INET, SOCK_DGRAM, 0)) < 0)
  {
    perror("socket fail");
    return EXIT_FAILURE;
  }

  //
  // set 1ms timeout, and re-use any recently open ports
  //
  setsockopt(Ptr->Socketid, SOL_SOCKET, SO_REUSEADDR, (void *)&yes , sizeof(yes));
  ReadTimeout.tv_sec = 0;
  ReadTimeout.tv_usec = 1000;
  setsockopt(Ptr->Socketid, SOL_SOCKET, SO_RCVTIMEO, (void *)&ReadTimeout , sizeof(ReadTimeout));

  //
  // bind application to the specified port
  //
  memset(&Ptr->addr_cmddata, 0, sizeof(struct sockaddr_in));
  Ptr->addr_cmddata.sin_family = AF_INET;
  Ptr->addr_cmddata.sin_addr.s_addr = htonl(INADDR_ANY);
  Ptr->addr_cmddata.sin_port = htons(Ptr->Portid);

  if(bind(Ptr->Socketid, (struct sockaddr *)&Ptr->addr_cmddata, sizeof(struct sockaddr_in)) < 0)
  {
    perror("bind");
    return EXIT_FAILURE;
  }

  struct sockaddr_in checkin;
  socklen_t len = sizeof(checkin);
  if(getsockname(Ptr->Socketid, (struct sockaddr *)&checkin, &len)==-1)
    perror("getsockname");

  Ptr->DDCid = DDCid;                       // set DDC number, for outgoing ports
  return 0;
}



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

  printf("setting ports\n");
  SetPort(VPORTDDCSPECIFIC, ntohs(*(uint16_t*)(PacketBuffer+5)));
  SetPort(VPORTDUCSPECIFIC, ntohs(*(uint16_t*)(PacketBuffer+7)));
  SetPort(VPORTHIGHPRIORITYTOSDR, ntohs(*(uint16_t*)(PacketBuffer+9)));
  SetPort(VPORTSPKRAUDIO, ntohs(*(uint16_t*)(PacketBuffer+13)));
  SetPort(VPORTDUCIQ, ntohs(*(uint16_t*)(PacketBuffer+15)));
  SetPort(VPORTHIGHPRIORITYFROMSDR, ntohs(*(uint16_t*)(PacketBuffer+11)));
  SetPort(VPORTMICAUDIO, ntohs(*(uint16_t*)(PacketBuffer+19)));

// DDC ports start at the transferred value then increment
  Port = ntohs(*(uint16_t*)(PacketBuffer+17));            // DDC0
  for (i=0; i<10; i++)
  {
    if(Port==0)
      SetPort(VPORTDDCIQ0+i, 0);
    else
      SetPort(VPORTDDCIQ0+i, Port+i);
  }  

// similarly, wideband ports start at the transferred value then increment
  Port = ntohs(*(uint16_t*)(PacketBuffer+21));            // DDC0
  for (i=0; i<2; i++)
  {
    if(Port==0)
      SetPort(VPORTWIDEBAND0+i, 0);
    else
      SetPort(VPORTWIDEBAND0+i, Port+i);
  }  

  return NULL;
}



//
// main program. Initialise, then handle incoming command/general data
// has a loop that reads & processes incoming command packets
// see protocol documentation
//
int main(void)
{
  int i, size;
//
// part written discovery reply packet
//
  uint8_t DiscoveryReply[VDISCOVERYREPLYSIZE] = 
  {
    0,0,0,0,                                      // sequence bytes
    2,                                            // 2 if not active; 3 if active
    0,0,0,0,0,0,                                  // SDR (raspberry i) MAC address
    1,                                            // board type. currently masquerading as "Hermes"
    38,                                           // protocol version 3.8
    10,                                           // this SDR firmware version. 
    0,0,0,0,0,0,                                  // Mercury, Metis, Penny version numbers
    4,                                            // 4DDC
    1,                                            // phase word
    0,                                            // endian mode
    0,0,                                          // beta version, reserved byte (total 25 useful bytes)
    0,0,0,0,0,0,0,0,0,0,                          // 10 bytes padding
    0,0,0,0,0,0,0,0,0,0,                          // 10 bytes padding
    0,0,0,0,0,0,0,0,0,0,0,0,0,0                   // 15 bytes padding
  };

  uint8_t CmdByte;                                                  // command word from PC app
  struct ifreq hwaddr;                                              // holds this device MAC address
  struct sockaddr_in addr_from;                                     // holds MAC address of source of incoming messages
  uint8_t UDPInBuffer[VDDCPACKETSIZE];                              // outgoing buffer
  struct iovec iovecinst;                                           // iovcnt buffer - 1 for each outgoing buffer
  struct msghdr datagram;                                           // multiple incoming message header


//
// setup Orion hardware
//
  OpenXDMADriver();
  CodecInitialise();
  InitialiseDACAttenROMs();
  InitialiseCWKeyerRamp();
  SetCWSidetoneEnabled(true);
  
  //
  // create socket for incoming data on the command port
  //
  MakeSocket(SocketData, 0);

  //
  // get this device MAC address
  //
  memset(&hwaddr, 0, sizeof(hwaddr));
  strncpy(hwaddr.ifr_name, "eth0", IFNAMSIZ - 1);
  ioctl(SocketData[VPORTCOMMAND].Socketid, SIOCGIFHWADDR, &hwaddr);
  for(i = 0; i < 6; ++i) DiscoveryReply[i + 5] = hwaddr.ifr_addr.sa_data[i];         // copy MAC to reply message

  MakeSocket(SocketData+VPORTDDCSPECIFIC, 0);            // create and bind a socket
  if(pthread_create(&DDCSpecificThread, NULL, IncomingDDCSpecific, (void*)&SocketData[VPORTDDCSPECIFIC]) < 0)
  {
    perror("pthread_create DDC specific");
    return EXIT_FAILURE;
  }
  pthread_detach(DDCSpecificThread);

  MakeSocket(SocketData+VPORTDUCSPECIFIC, 0);            // create and bind a socket
  if(pthread_create(&DUCSpecificThread, NULL, IncomingDUCSpecific, (void*)&SocketData[VPORTDUCSPECIFIC]) < 0)
  {
    perror("pthread_create DUC specific");
    return EXIT_FAILURE;
  }
  pthread_detach(DUCSpecificThread);

  MakeSocket(SocketData+VPORTHIGHPRIORITYTOSDR, 0);            // create and bind a socket
  if(pthread_create(&HighPriorityToSDRThread, NULL, IncomingHighPriority, (void*)&SocketData[VPORTHIGHPRIORITYTOSDR]) < 0)
  {
    perror("pthread_create High priority to SDR");
    return EXIT_FAILURE;
  }
  pthread_detach(HighPriorityToSDRThread);

  MakeSocket(SocketData+VPORTSPKRAUDIO, 0);            // create and bind a socket
  if(pthread_create(&SpkrAudioThread, NULL, IncomingSpkrAudio, (void*)&SocketData[VPORTSPKRAUDIO]) < 0)
  {
    perror("pthread_create speaker audio");
    return EXIT_FAILURE;
  }
  pthread_detach(SpkrAudioThread);

  MakeSocket(SocketData+VPORTDUCIQ, 0);            // create and bind a socket
  if(pthread_create(&DUCIQThread, NULL, IncomingDUCIQ, (void*)&SocketData[VPORTDUCIQ]) < 0)
  {
    perror("pthread_create DUC I/Q");
    return EXIT_FAILURE;
  }
  pthread_detach(DUCIQThread);

//
// and for now create just one outgoing data thread for DDC 0
//
  MakeSocket(SocketData+VPORTDDCIQ0, 0);
  if(pthread_create(&DDCIQThread[0], NULL, OutgoingDDCIQ, (void*)&SocketData[VPORTDDCIQ0]) < 0)
  {
    perror("pthread_create DUC I/Q");
    return EXIT_FAILURE;
  }
  pthread_detach(DDCIQThread[0]);


  //
  // now main processing loop. Process received Command packets arriving at port 1024
  // these are identified by the command byte (byte 4)
  // cmd=00: general packet
  // cmd=02: discovery
  // cmd=03: set IP address (not supported)
  // cmd=04: erase (not supported)
  // cmd=05: program (not supported)
  //
  while(1)
  {
    memset(&iovecinst, 0, sizeof(struct iovec));
    memset(&datagram, 0, sizeof(datagram));
    iovecinst.iov_base = &UDPInBuffer;                  // set buffer for incoming message number i
    iovecinst.iov_len = VDDCPACKETSIZE;
    datagram.msg_iov = &iovecinst;
    datagram.msg_iovlen = 1;
    datagram.msg_name = &addr_from;
    datagram.msg_namelen = sizeof(addr_from);
    size = recvmsg(SocketData[0].Socketid, &datagram, 0);         // get one message. If it times out, ges size=-1
    if(size < 0 && errno != EAGAIN)
    {
      perror("recvfrom");
      return EXIT_FAILURE;
    }


//
// only process packets of length 60 bytes on this port, to exclude protocol 1 discovery for example.
// (that means we can't handle the programming packet but we don't use that anyway)
//
    CmdByte = UDPInBuffer[4];
    if(size==VDISCOVERYSIZE)  
      switch(CmdByte)
      {
        //
        // general packet. Get the port numbers and establish listener threads
        //
        case 0:
          printf("P2 General packet to SDR, size= %d\n", size);
          //
          // get "from" MAC address and port; this is where the data goes back to
          //
          memset(&reply_addr, 0, sizeof(reply_addr));
          reply_addr.sin_family = AF_INET;
          reply_addr.sin_addr.s_addr = addr_from.sin_addr.s_addr;
          reply_addr.sin_port = addr_from.sin_port;                       // (but each outgoing thread needs to set its own sin_port)
          HandleGeneralPacket(UDPInBuffer);
          break;

        //
        // discovery packet
        //
        case 2:
          printf("P2 Discovery packet\n");
          DiscoveryReply[4] = 2 + active_thread;                             // response 2 if not active, 3 if running
          memset(&UDPInBuffer, 0, VDISCOVERYREPLYSIZE);
          memcpy(&UDPInBuffer, DiscoveryReply, VDISCOVERYREPLYSIZE);
          sendto(SocketData[0].Socketid, &UDPInBuffer, VDISCOVERYREPLYSIZE, 0, (struct sockaddr *)&addr_from, sizeof(addr_from));
          break;

        case 3:
        case 4:
        case 5:
          printf("Unsupported packet\n");
          break;

        default:
          break;

      }// end switch (packet type)

//
// now do any "post packet" processing
//
  } //while(1)
  close(SocketData[0].Socketid);                          // close incoming data socket

  return EXIT_SUCCESS;
}




//
// listener thread for incoming DDC specific packets
//
void *IncomingDDCSpecific(void *arg)                    // listener thread
{
  struct ThreadSocketData *ThreadData;                  // socket etc data for this thread
  struct sockaddr_in addr_from;                         // holds MAC address of source of incoming messages
  uint8_t UDPInBuffer[VDDCPACKETSIZE];                  // outgoing buffer
  struct iovec iovecinst;                               // iovcnt buffer - 1 for each outgoing buffer
  struct msghdr datagram;                               // multiple incoming message header
  int size;                                             // UDP datagram length

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
    iovecinst.iov_len = VDDCPACKETSIZE;
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



//
// listener thread for incoming DUC specific packets
//
void *IncomingDUCSpecific(void *arg)                    // listener thread
{
  struct ThreadSocketData *ThreadData;                  // socket etc data for this thread
  struct sockaddr_in addr_from;                         // holds MAC address of source of incoming messages
  uint8_t UDPInBuffer[VDDCPACKETSIZE];                  // outgoing buffer
  struct iovec iovecinst;                               // iovcnt buffer - 1 for each outgoing buffer
  struct msghdr datagram;                               // multiple incoming message header
  int size;                                             // UDP datagram length

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
    iovecinst.iov_len = VDDCPACKETSIZE;
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
    if(size == VDUCSPECIFICSIZE)
    {
      printf("DUC packet received\n");
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



//
// listener thread for incoming high priority packets
//
void *IncomingHighPriority(void *arg)                   // listener thread
{
  struct ThreadSocketData *ThreadData;                  // socket etc data for this thread
  struct sockaddr_in addr_from;                         // holds MAC address of source of incoming messages
  uint8_t UDPInBuffer[VDDCPACKETSIZE];                  // outgoing buffer
  struct iovec iovecinst;                               // iovcnt buffer - 1 for each outgoing buffer
  struct msghdr datagram;                               // multiple incoming message header
  int size;                                             // UDP datagram length
  bool RunBit;                                          // true if "run" bit set
  uint32_t DDCPhaseIncrement;                           // delta phase for a DDC

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
    iovecinst.iov_len = VDDCPACKETSIZE;
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
    if(size == VHIGHPRIOTIYTOSDRSIZE)
    {
      printf("high priority packet received\n");
      RunBit = (bool)(UDPInBuffer[4]&1);
      if(RunBit)
        printf("enabling streaming threads\n");
      for(int i=0; i < VPORTTABLESIZE; i++)
        if(RunBit)
          SocketData[i].Cmdid |= VBITDATARUN;
        else
          SocketData[i].Cmdid &= ~VBITDATARUN;
      // get DDC0 phase word and send to FPGA
      DDCPhaseIncrement = ntohl(*(uint32_t *)(UDPInBuffer+9));
      printf("DDC0 delta phi = %d\n", DDCPhaseIncrement);
      RegisterWrite(0xA008, DDCPhaseIncrement);
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



//
// listener thread for incoming DUC I/Q packets
//
void *IncomingDUCIQ(void *arg)                          // listener thread
{
  struct ThreadSocketData *ThreadData;                  // socket etc data for this thread
  struct sockaddr_in addr_from;                         // holds MAC address of source of incoming messages
  uint8_t UDPInBuffer[VDDCPACKETSIZE];                  // outgoing buffer
  struct iovec iovecinst;                               // iovcnt buffer - 1 for each outgoing buffer
  struct msghdr datagram;                               // multiple incoming message header
  int size;                                             // UDP datagram length

  ThreadData = (struct ThreadSocketData *)arg;
  ThreadData->Active = true;
  printf("spinning up DUC I/Q thread with port %d\n", ThreadData->Portid);
  //
  // main processing loop
  //
  while(1)
  {
    memset(&iovecinst, 0, sizeof(struct iovec));
    memset(&datagram, 0, sizeof(datagram));
    iovecinst.iov_base = &UDPInBuffer;                  // set buffer for incoming message number i
    iovecinst.iov_len = VDDCPACKETSIZE;
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
    if(size == VDUCIQSIZE)
    {
      printf("DUC I/Q data packet received\n");
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



//
// listener thread for incoming DDC (speaker) audio packets
//
void *IncomingSpkrAudio(void *arg)                      // listener thread
{
  struct ThreadSocketData *ThreadData;                  // socket etc data for this thread
  struct sockaddr_in addr_from;                         // holds MAC address of source of incoming messages
  uint8_t UDPInBuffer[VDDCPACKETSIZE];                  // outgoing buffer
  struct iovec iovecinst;                               // iovcnt buffer - 1 for each outgoing buffer
  struct msghdr datagram;                               // multiple incoming message header
  int size;                                             // UDP datagram length

  ThreadData = (struct ThreadSocketData *)arg;
  ThreadData->Active = true;
  printf("spinning up speaker audio thread with port %d\n", ThreadData->Portid);
  //
  // main processing loop
  //
  while(1)
  {
    memset(&iovecinst, 0, sizeof(struct iovec));
    memset(&datagram, 0, sizeof(datagram));
    iovecinst.iov_base = &UDPInBuffer;                  // set buffer for incoming message number i
    iovecinst.iov_len = VDDCPACKETSIZE;
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
    if(size == VSPEAKERAUDIOSIZE)
    {
      printf("speaker audio packet received\n");
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




//
// global holding the current step of C&C data. Each new USB frame updates this.
//
#define VDMABUFFERSIZE 32768									      // memory buffer to reserve
#define VALIGNMENT 4096                             // buffer alignment
#define VBASE 0x1000									              // DMA start at 4K into buffer
#define VBASE 0x1000                                // offset into I/Q buffer for DMA to start
#define VDMATRANSFERSIZE 4096                       // read 4K at a time
#define AXIBaseAddress 0x18000									    // address of StreamRead/Writer IP (Litefury only!)

#define VDDCPACKETSIZE 1444
#define VIQSAMPLESPERFRAME 238                      // total I/Q samples in one DDC packet
#define VIQBYTESPERFRAME 6*VIQSAMPLESPERFRAME       // total bytes in one outgoing frame

//
// this runs as its own thread to send outgoing data
// thread initiated after a "Start" command
// will be instructed to stop & exit by main loop setting enable_thread to 0
// this code signals thread terminated by setting active_thread = 0
//
void *OutgoingDDCIQ(void *arg)
{
//
// memory buffers
//
  uint8_t* IQReadBuffer = NULL;											// data for DMA read from DDC
	uint32_t IQBufferSize = VDMABUFFERSIZE;
  bool InitError = false;                         // becomes true if we get an initialisation error
	unsigned char* IQReadPtr;								        // pointer for reading out an I or Q sample
	unsigned char* IQHeadPtr;								        // ptr to 1st free location in I/Q memory
	unsigned char* IQBasePtr;								        // ptr to DMA location in I/Q memory
	uint32_t ResidueBytes;
	uint32_t Depth = 0;
	int DMAReadfile_fd = -1;											  // DMA read file device
	uint32_t RegisterValue;


  struct ThreadSocketData *ThreadData;            // socket etc data for this thread
  struct sockaddr_in DestAddr;                    // destination address for outgoing data


//
// variables for outgoing UDP frame
//
  struct iovec iovecinst;                                 // instance of iovec
  struct msghdr datagram;
  uint8_t UDPBuffer[VDDCPACKETSIZE];                      // DDC frame buffer
  uint32_t SequenceCounter = 0;                           // UDP sequence count

//
// initialise. Create memory buffers and open DMA file devices
//
  ThreadData = (struct ThreadSocketData *)arg;
  ThreadData->Active = true;
  printf("spinning up outgoing I/Q thread with port %d\n", ThreadData->Portid);

	posix_memalign((void **)&IQReadBuffer, VALIGNMENT, IQBufferSize);
	if(!IQReadBuffer)
	{
		printf("I/Q read buffer allocation failed\n");
		InitError = true;
	}
	IQReadPtr = IQReadBuffer + VBASE;							// offset 4096 bytes into buffer
	IQHeadPtr = IQReadBuffer + VBASE;
	IQBasePtr = IQReadBuffer + VBASE;
  memset(IQReadBuffer, 0, IQBufferSize);


//
// open DMA device driver
//
	DMAReadfile_fd = open("/dev/xdma0_c2h_0", O_RDWR);
	if(DMAReadfile_fd < 0)
	{
		printf("XDMA read device open failed\n");
		InitError = true;
	}


//
// write 0 to GPIO to clear FIFO; then set 2 to GPIO for normal operation
// then read depth
//
	RegisterWrite(0xA000, 0);				// write to the GPIO register
	RegisterWrite(0xA000, 2);				// write to the GPIO register
	printf("GPIO Register written with value=0 then 2 to reset FIFO\n");
	RegisterValue = RegisterRead(0x9000);				// read the FIFO Depth register
	printf("FIFO Depth register = %08x (should be 0)\n", RegisterValue);
	Depth=0;



//
// thread loop. runs continuously until commanded by main loop to exit
// for now: add 1 RX data + mic data at 48KHz sample rate. Mic data is constant zero.
// while there is enough I/Q data, make outgoing packets;
// when not enough data, read more.
//
  while(!(ThreadData->Cmdid & VBITDATARUN))
  {
    usleep(100);
  }
  printf("starting outgoing data\n");
  //
  // initialise outgoing DDC packet
  //
  memcpy(&DestAddr, &reply_addr, sizeof(struct sockaddr_in));           // local copy of PC destination address
  memset(&iovecinst, 0, sizeof(struct iovec));
  memset(&datagram, 0, sizeof(datagram));
  iovecinst.iov_base = UDPBuffer;
  iovecinst.iov_len = VDDCPACKETSIZE;
  datagram.msg_iov = &iovecinst;
  datagram.msg_iovlen = 1;
  datagram.msg_name = &DestAddr;                   // MAC addr & port to send to
  datagram.msg_namelen = sizeof(DestAddr);

//
// write 3 to GPIO to enable FIFO writes
//
	RegisterWrite(0xA000, 3);				// write to the GPIO register
	printf("GPIO Register written with value=3, enabling writes\n");
  while(!InitError)
  {
	
    //
    // while there is enough I/Q data, make DDC Packets
    //
    while((IQHeadPtr - IQReadPtr)>VIQBYTESPERFRAME)
    {
      *(uint32_t *)UDPBuffer = htonl(SequenceCounter++);        // add sequence count
      memset(UDPBuffer+4, 0,8);                                 // clear the timestamp data
      *(uint16_t *)(UDPBuffer+12) = htons(24);                         // bits per sample
      *(uint32_t *)(UDPBuffer+14) = htons(VIQSAMPLESPERFRAME);         // I/Q samples for ths frame
      //
      // now add I/Q data & send outgoing packet
      //
      memcpy(UDPBuffer + 16, IQReadPtr, VIQBYTESPERFRAME);
      IQReadPtr += VIQBYTESPERFRAME;

      int Error;

      Error = sendmsg(ThreadData -> Socketid, &datagram, 0);
      if(Error == -1)
      {
        printf("Send Error, errno=%d\n",errno);
        printf("socket id = %d\n", ThreadData -> Socketid);
        InitError=true;
      }
    }
    //
    // now bring in more data via DMA
    // first copy any residue to the start of the buffer (before the DMA point)
//
		ResidueBytes = IQHeadPtr- IQReadPtr;
//		printf("Residue = %d bytes\n",ResidueBytes);
		if(ResidueBytes != 0)					// if there is residue
		{
			memcpy(IQBasePtr-ResidueBytes, IQReadPtr, ResidueBytes);
			IQReadPtr = IQBasePtr-ResidueBytes;
		}
		else
			IQReadPtr = IQBasePtr;
//
// now wait until there is data, then DMA it
//
		Depth = RegisterRead(0x9000);				// read the user access register
//		printf("read: depth = %d\n", Depth);
		while(Depth < 512)			// 512 locations = 4K bytes
		{
			usleep(1000);								// 1ms wait
			Depth = RegisterRead(0x9000);				// read the user access register
//			printf("read: depth = %d\n", Depth);
		}

//		printf("DMA read %d bytes from destination to base\n", VDMATRANSFERSIZE);
		DMAReadFromFPGA(DMAReadfile_fd, IQBasePtr, VDMATRANSFERSIZE, AXIBaseAddress);
		IQHeadPtr = IQBasePtr + VDMATRANSFERSIZE;
  }     // end of while(!InitError) loop

//
// tidy shutdown of the thread
//
  printf("shutting down DDC outgoing thread\n");
  ThreadData->Active = false;                   // signal closed
	close(DMAReadfile_fd);
  free(IQReadBuffer);
  return NULL;
}

