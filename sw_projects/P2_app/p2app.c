/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
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
#include <semaphore.h>
#include<signal.h>

#include "../common/saturntypes.h"
#include "../common/hwaccess.h"                     // access to PCIe read & write
#include "../common/saturnregisters.h"              // register I/O for Saturn
#include "../common/codecwrite.h"                   // codec register I/O for Saturn
#include "../common/version.h"                      // version I/O for Saturn
#include "../common/auxadc.h"                      // version I/O for Saturn

#include "threaddata.h"
#include "generalpacket.h"
#include "IncomingDDCSpecific.h"
#include "IncomingDUCSpecific.h"
#include "InHighPriority.h"
#include "InDUCIQ.h"
#include "InSpkrAudio.h"
#include "OutMicAudio.h"
#include "OutDDCIQ.h"
#include "OutHighPriority.h"

#define P2APPVERSION 14
//------------------------------------------------------------------------------------------
// VERSION History
// V14:              added ATU tune request to IO6 bit position; FIFO under and overflow detection;
//                   changed FIFO sizes; debug can be enabled as runtime setting; enable/disable ext speaker;
//                   network timeout
// V13, 18/8/2023:   inverted IO8 sense for piHPSDR-initiaited CW
// V12, 29/7/2023:   CW changes to set RX attenuation on TX from protocol bytes 58, 59;
//                   CW breakin properly enabled; CW peyer disabled if p2app not active;
//                   CW changes to minimise delay reporting to prototol 2


extern sem_t DDCInSelMutex;                 // protect access to shared DDC input select register
extern sem_t DDCResetFIFOMutex;             // protect access to FIFO reset register
extern sem_t RFGPIOMutex;                   // protect access to RF GPIO register
extern sem_t CodecRegMutex;                 // protect writes to codec

struct sockaddr_in reply_addr;              // destination address for outgoing data

bool IsTXMode;                              // true if in TX
bool SDRActive;                             // true if this SDR is running at the moment
bool ReplyAddressSet = false;               // true when reply address has been set
bool StartBitReceived = false;              // true when "run" bit has been set
bool NewMessageReceived = false;            // set whenever a message is received
bool ExitRequested = false;                 // true if "exit checking" thread requests shutdown
bool SkipExitCheck = false;                 // true to skip "exit checking", if running as a service
bool ThreadError = false;                   // true if a thread reports an error
bool UseDebug = false;                      // true if to enable debugging


#define SDRBOARDID 1                        // Hermes
#define SDRSWVERSION 1                      // version of this software
#define VDISCOVERYSIZE 60                   // discovery packet
#define VDISCOVERYREPLYSIZE 60              // reply packet
#define VWIDEBANDSIZE 1028                  // wideband scalar samples
#define VCONSTTXAMPLSCALEFACTOR 0x0001FFFF  // 18 bit scale value - set to 1/2 of full scale

struct ThreadSocketData SocketData[VPORTTABLESIZE] =
{
  {0, 0, 1024, "Cmd", false,{}, 0, 0},                      // command (incoming) thread
  {0, 0, 1025, "DDC Specific", false,{}, 0, 0},             // DDC specifc (incoming) thread
  {0, 0, 1026, "DUC Specific", false,{}, 0, 0},             // DUC specific (incoming) thread
  {0, 0, 1027, "High Priority In", false,{}, 0, 0},         // High Priority (incoming) thread
  {0, 0, 1028, "Spkr Audio", false,{}, 0, 0},               // Speaker Audio (incoming) thread
  {0, 0, 1029, "DUC I/Q", false,{}, 0, 0},                  // DUC IQ (incoming) thread
  {0, 0, 1025, "High Priority Out", false,{}, 0, 0},        // High Priority (outgoing) thread
  {0, 0, 1026, "Mic Audio", false,{}, 0, 0},                // Mic Audio (outgoing) thread
  {0, 0, 1035, "DDC I/Q 0", false,{}, 0, 0},                // DDC IQ 0 (outgoing) thread
  {0, 0, 1036, "DDC I/Q 1", false,{}, 0, 0},                // DDC IQ 1 (outgoing) thread
  {0, 0, 1037, "DDC I/Q 2", false,{}, 0, 0},                // DDC IQ 2 (outgoing) thread
  {0, 0, 1038, "DDC I/Q 3", false,{}, 0, 0},                // DDC IQ 3 (outgoing) thread
  {0, 0, 1039, "DDC I/Q 4", false,{}, 0, 0},                // DDC IQ 4 (outgoing) thread
  {0, 0, 1040, "DDC I/Q 5", false,{}, 0, 0},                // DDC IQ 5 (outgoing) thread
  {0, 0, 1041, "DDC I/Q 6", false,{}, 0, 0},                // DDC IQ 6 (outgoing) thread
  {0, 0, 1042, "DDC I/Q 7", false,{}, 0, 0},                // DDC IQ 7 (outgoing) thread
  {0, 0, 1043, "DDC I/Q 8", false,{}, 0, 0},                // DDC IQ 8 (outgoing) thread
  {0, 0, 1044, "DDC I/Q 9", false,{}, 0, 0},                // DDC IQ 9 (outgoing) thread
  {0, 0, 1027, "Wideband 0", false,{}, 0, 0},               // Wideband 0 (outgoing) thread
  {0, 0, 1028, "Wideband 1", false,{}, 0, 0}                // Wideband 1 (outgoing) thread
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
pthread_t MicThread;
pthread_t HighPriorityFromSDRThread;
pthread_t CheckForExitThread;                 // thread looks for types "exit" command
pthread_t CheckForNoActivityThread;           // thread looks for inactvity

void sig_handler(int signo)
{
    if (signo == SIGINT)
        printf("received SIGINT\n");
    ExitRequested = true;
}

//
// function to check if any threads are still active
// loop through the table; report if any are true.
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
// this runs as its own thread to monitor command line activity. A string "exist" exits the application. 
// thread initiated at the start.
//
void* CheckForExitCommand(void *arg)
{
  char ch;
  printf("spinning up Check For Exit thread\n");
  
  while (1)
  {
    usleep(10000);
    ch = getchar();
    if((ch == 'x') || (ch == 'X'))
    {
      ExitRequested = true;
      break;
    }
  }
}


//
// this runs as its own thread to see if messages have stopped being received.
// if nomessages in a second, goes back to "inactive" state.
//
void* CheckForActivity(void *arg)
{
  bool PreviouslyActiveState;               
  while(1)
  {
    sleep(1);                                   // wait for 1 second
    PreviouslyActiveState = SDRActive;          // see if active on entry
    if (!NewMessageReceived && HW_Timer_Enable) // if no messages received,
    {
      SDRActive = false;                        // set back to inactive
      SetTXEnable(false);
      EnableCW(false, false);
      ReplyAddressSet = false;
      StartBitReceived = false;
      if(PreviouslyActiveState)
        printf("Reverted to Inactive State after no activity\n");
    }
    NewMessageReceived = false;
  }
}




//
// Shutdown()
// perform ordely shutdown of the program
//
void Shutdown()
{
  close(SocketData[0].Socketid);                          // close incoming data socket
  sem_destroy(&DDCInSelMutex);
  sem_destroy(&DDCResetFIFOMutex);
  sem_destroy(&RFGPIOMutex);
  sem_destroy(&CodecRegMutex);
  SetMOX(false);
  SetTXEnable(false);
  EnableCW(false, false);
}



//
// main program. Initialise, then handle incoming command/general data
// has a loop that reads & processes incoming command packets
// see protocol documentation
// 
// if invoked "./p2app" - ADCs selected as normal
// if invoked "./p2app 1900000" - ADC1 and ADC2 inputs set to DDS test source at 1900000Hz
//
int main(int argc, char *argv[])
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
    10,                                           // board type. changed from "orion mk2" to "saturn"
    39,                                           // protocol version 3.8
    20,                                           // this SDR firmware version. >17 to enable QSK
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

  uint32_t TestFrequency;                                           // test source DDS freq
  int CmdOption;                                                    // command line option
  char BuildDate[]=GIT_DATE;

  //
  // initialise register access semaphores
  //
  sem_init(&DDCInSelMutex, 0, 1);                                   // for DDC input select register
  sem_init(&DDCResetFIFOMutex, 0, 1);                               // for FIFO reset register
  sem_init(&RFGPIOMutex, 0, 1);                                     // for RF GPIO register
  sem_init(&CodecRegMutex, 0, 1);                                   // for codec writes

//
// setup Saturn hardware
//
  printf("SATURN Protocol 2 App. press 'x <enter>' in console to close\n");

  OpenXDMADriver();
  PrintVersionInfo();
  printf("p2app client app software Version:%d Build Date:%s\n", P2APPVERSION, BuildDate);
  PrintAuxADCInfo();
  if (IsFallbackConfig())
      printf("FPGA load is a fallback - you should re-flash the primary FPGA image!\n");

  CodecInitialise();
  InitialiseDACAttenROMs();
  InitialiseCWKeyerRamp(true, 5000);                                // 5 ms ramp, P2
  SetCWSidetoneEnabled(true);
  SetTXProtocol(true);                                              // set to protocol 2
  SetTXModulationSource(eIQData);                                   // disable debug options
  HandlerSetEERMode(false);                                         // no EER
  SetByteSwapping(true);                                            // h/w to generate network byte order
  SetSpkrMute(false);
  SetTXAmplitudeScaling(VCONSTTXAMPLSCALEFACTOR);
  // SetTXEnable(true);                                             // now only enabled if SDR active
  EnableAlexManualFilterSelect(true);
  SetBalancedMicInput(false);

  if (signal(SIGINT, sig_handler) == SIG_ERR)
    printf("\ncan't catch SIGINT\n");

//
// start up thread to check for no longer getting messages, to set back to inactive
//
  if(pthread_create(&CheckForNoActivityThread, NULL, CheckForActivity, NULL) < 0)
  {
    perror("pthread_create check for exit");
    return EXIT_FAILURE;
  }
  pthread_detach(CheckForNoActivityThread);

//
// option string needs a colon after each option letter that has a parameter after it
// and it has a leading colon to suppress error messages
//
  while((CmdOption = getopt(argc, argv, ":i:f:h:m:sd")) != -1)
  {
    switch(CmdOption)
    {
      case 'h':
        printf("usage: ./p2app <optional arguments>\n");
        printf("optional arguments:\n");
        printf("-f <frequency in Hz> turns on test source for all DDCs\n");
        printf("-i saturn     board responds as board id = Saturn\n");
        printf("-i orionmk2   board responds as board id = Orion mk 2\n");
        printf("-m xlr        selects balanced XLR microphone input\n");
        printf("-m jack       selects unbalanced 3.5mm microphone input\n");
        printf("-s skip checking for exit keys, run as service\n");
        return EXIT_SUCCESS;
        break;

      case 'i':
        if(strcmp(optarg,"saturn") == 0)
        {
          printf("Discovery will respond as Saturn\n");
          DiscoveryReply[11] = 10;
        }
        else if(strcmp(optarg,"orionmk2") == 0)
        {
          printf("Discovery will respond as Orion mk 2\n");
          DiscoveryReply[11] = 5;
        }
        else
        {
          printf("error parsing board id. Values must be lower case\n");
          printf("-i saturn     board responds as board id = Saturn\n");
          printf("-i orionmk2   board responds as board id = Orion mk 2\n");
          return EXIT_SUCCESS;
        }
        break;


      case 'm':
        if(strcmp(optarg,"xlr") == 0)
        {
          printf("XLR mic input selected\n");
          SetBalancedMicInput(true);
        }
        else if(strcmp(optarg,"jack") == 0)
        {
          printf("unbalanced mic input selected\n");
          SetBalancedMicInput(false);
        }
        else
        {
          printf("error parsing microphone type. Values must be lower case\n");
          printf("-m xlr    selects balanced XLR microphone input\n\n");
          printf("-m jack   selects unbalanced 3.5mm microphone input\n");
          return EXIT_SUCCESS;
        }
        break;

      case 'f':
        TestFrequency = (atoi(optarg));
        SetTestDDSFrequency(TestFrequency, false);   
        UseTestDDSSource();         
        printf ("Test source selected, frequency = %dHz\n", TestFrequency);                  
        break;

      case 's':
        printf ("Skipping check for exit keys\n");                  
        SkipExitCheck = true;
        break;

      case 'd':
        UseDebug = true;
    }
  }
  printf("\n");

//
// start up thread for exit command checking
//
  if (SkipExitCheck == false)
  {
    if(pthread_create(&CheckForExitThread, NULL, CheckForExitCommand, NULL) < 0)
    {
      perror("pthread_create check for exit");
      return EXIT_FAILURE;
    }
  }
  pthread_detach(CheckForExitThread);

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
// create outgoing mic data thread
// note this shares a port with incoming DUC specific, so don't create a new port
// instead copy socket settings from DUCSPECIFIC socket:
//
  SocketData[VPORTMICAUDIO].Socketid = SocketData[VPORTDUCSPECIFIC].Socketid;
  memcpy(&SocketData[VPORTMICAUDIO].addr_cmddata, &SocketData[VPORTDUCSPECIFIC].addr_cmddata, sizeof(struct sockaddr_in));
  if(pthread_create(&MicThread, NULL, OutgoingMicSamples, (void*)&SocketData[VPORTMICAUDIO]) < 0)
  {
    perror("pthread_create Mic");
    return EXIT_FAILURE;
  }
  pthread_detach(MicThread);





//
// create outgoing high priority data thread
// note this shares a port with incoming DDC specific, so don't create a new port
// instead copy socket settings from VPORTDDCSPECIFIC socket:
//
  SocketData[VPORTHIGHPRIORITYFROMSDR].Socketid = SocketData[VPORTDDCSPECIFIC].Socketid;
  memcpy(&SocketData[VPORTHIGHPRIORITYFROMSDR].addr_cmddata, &SocketData[VPORTDDCSPECIFIC].addr_cmddata, sizeof(struct sockaddr_in));
  if(pthread_create(&HighPriorityFromSDRThread, NULL, OutgoingHighPriority, (void*)&SocketData[VPORTHIGHPRIORITYFROMSDR]) < 0)
  {
    perror("pthread_create outgoing hi priority");
    return EXIT_FAILURE;
  }
  pthread_detach(HighPriorityFromSDRThread);


//
// and for now create just one outgoing DDC data thread for DDC 0
// create all the sockets though!
//
  MakeSocket(SocketData + VPORTDDCIQ0, 0);
  MakeSocket(SocketData + VPORTDDCIQ1, 0);
  MakeSocket(SocketData + VPORTDDCIQ2, 0);
  MakeSocket(SocketData + VPORTDDCIQ3, 0);
  MakeSocket(SocketData + VPORTDDCIQ4, 0);
  MakeSocket(SocketData + VPORTDDCIQ5, 0);
  MakeSocket(SocketData + VPORTDDCIQ6, 0);
  MakeSocket(SocketData + VPORTDDCIQ7, 0);
  MakeSocket(SocketData + VPORTDDCIQ8, 0);
  MakeSocket(SocketData + VPORTDDCIQ9, 0);
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
    size = recvmsg(SocketData[0].Socketid, &datagram, 0);         // get one message. If it times out, gets size=-1
    if(size < 0 && errno != EAGAIN)
    {
      perror("recvfrom, port 1024");
      return EXIT_FAILURE;
    }
    if(ExitRequested)
      break;
    if(ThreadError)
      break;


//
// only process packets of length 60 bytes on this port, to exclude protocol 1 discovery for example.
// (that means we can't handle the programming packet but we don't use that anyway)
//
    CmdByte = UDPInBuffer[4];
    if(size==VDISCOVERYSIZE)  
    {
      NewMessageReceived = true;
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
          ReplyAddressSet = true;
          if(ReplyAddressSet && StartBitReceived)
          {
            SDRActive = true;                                       // only set active if we have start bit too
            SetTXEnable(true);
          }
          break;

        //
        // discovery packet
        //
        case 2:
          printf("P2 Discovery packet\n");
          if(SDRActive)
            DiscoveryReply[4] = 3;                             // response 2 if not active, 3 if running
          else
            DiscoveryReply[4] = 2;                             // response 2 if not active, 3 if running

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
    }
//
// now do any "post packet" processing
//
  } //while(1)
  if(ThreadError)
    printf("Thread error reported - exiting\n");
  //
  // clean exit
  //
  printf("Exiting\n");
  Shutdown();
  return EXIT_SUCCESS;
}




