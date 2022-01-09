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


int socket_cmddata;                               // socket for PC to SDR data
struct sockaddr_in reply_addr;                // destination address for outgoing data

int enable_thread = 0;                      // true if outgoing data thread enabled
int active_thread = 0;                      // true if outgoing thread is running

void *OutgoingDDCIQ(void *arg);


#define SDRBOARDID 1                    // Hermes
#define SDRSWVERSION 1                  // version of this software
#define VDDCPACKETSIZE 1444             // each DDC packet
#define VDISCOVERYREPLYSIZE 60          // reply packet


//
// main program. Initialise, then handle incoming command/general data
// has a loop that reads & processes incoming command packets
// see protocol documentation
//
int main(void)
{
  int i, size;
  pthread_t thread;

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
  struct sockaddr_in addr_cmddata, addr_from[10];                   // holds MAC address of source of incoming messages
  uint8_t UDPInBuffer[VDDCPACKETSIZE];                              // outgoing buffer
  struct iovec iovecinst;                                           // iovcnt buffer - 1 for each outgoing buffer
  struct msghdr datagram;                                           // multiple incoming message header
  struct timeval ReadTimeout;                                       // read timeout
  int yes = 1;


//
// setup Orion hardware
//
  OpenXDMADriver();
  CodecInitialise();
  InitialiseDACAttenROMs();
  InitialiseCWKeyerRamp();
  SetCWSidetoneEnabled(true);
  


  //
  // create socket for incoming data
  //
  if((socket_cmddata = socket(AF_INET, SOCK_DGRAM, 0)) < 0)
  {
    perror("socket");
    return EXIT_FAILURE;
  }

  //
  // get this device MAC address
  //
  memset(&hwaddr, 0, sizeof(hwaddr));
  strncpy(hwaddr.ifr_name, "eth0", IFNAMSIZ - 1);
  ioctl(socket_cmddata, SIOCGIFHWADDR, &hwaddr);
  for(i = 0; i < 6; ++i) DiscoveryReply[i + 5] = hwaddr.ifr_addr.sa_data[i];         // copy MAC to reply message

  setsockopt(socket_cmddata, SOL_SOCKET, SO_REUSEADDR, (void *)&yes , sizeof(yes));

  //
  // set 1ms timeout
  //
  ReadTimeout.tv_sec = 0;
  ReadTimeout.tv_usec = 1000;
  setsockopt(socket_cmddata, SOL_SOCKET, SO_RCVTIMEO, (void *)&ReadTimeout , sizeof(ReadTimeout));

  //
  // bind application to port 1024
  //
  memset(&addr_cmddata, 0, sizeof(addr_cmddata));
  addr_cmddata.sin_family = AF_INET;
  addr_cmddata.sin_addr.s_addr = htonl(INADDR_ANY);
  addr_cmddata.sin_port = htons(1024);

  if(bind(socket_cmddata, (struct sockaddr *)&addr_cmddata, sizeof(addr_cmddata)) < 0)
  {
    perror("bind");
    return EXIT_FAILURE;
  }


  //
  // now main processing loop. Process received Command packets arriving at port 1024
  // these are identified by the command byter (byte 4)
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
    datagram.msg_name = &addr_from[i];
    datagram.msg_namelen = sizeof(addr_from[i]);
    UDPInBuffer[4] = 0xFF;                                // set to "unknown packet"
    size = recvmsg(socket_cmddata, &datagram, 0);         // get one message
    if(size < 0 && errno != EAGAIN)
    {
      perror("recvfrom");
      return EXIT_FAILURE;
    }

    CmdByte = UDPInBuffer[4];
    switch(CmdByte)
    {
      //
      // general packet
      //
      case 0:
        printf("General packet to SDR\n");
        break;

      //
      // discovery packet
      //
      case 2:
        printf("Discovery packet\n");
        DiscoveryReply[4] = 2 + active_thread;                             // response 2 if not active, 3 if running
        memset(&UDPInBuffer, 0, VDISCOVERYREPLYSIZE);
        memcpy(&UDPInBuffer, DiscoveryReply, VDISCOVERYREPLYSIZE);
        sendto(socket_cmddata, &UDPInBuffer, VDISCOVERYREPLYSIZE, 0, (struct sockaddr *)&addr_from[i], sizeof(addr_from[i]));

        break;

      case 3:
      case 4:
      case 5:
        printf("Unsupported packet\n");
        break;

      default:
        break;

      // Metis STOP command from PC
      // terminate outgoing thread
      case 0x0004feef:
        enable_thread = 0;                                        // signal thread to terminate
        while(active_thread) usleep(1000);                        // sleep until thread has terminated
        break;


      // Metis START commands to PC (01=IQ only; 02=wideband only; 03=both)
      // initialise settings for outgoing data thread and start it
      case 0x0104feef:
      case 0x0204feef:
      case 0x0304feef:
        printf("received metis START command\n");
        enable_thread = 0;                                // command outgoing thread to stop
        while(active_thread) usleep(1000);                // wait until it has stopped

        //
        // get from MAC address and port; this is where the data goes back to
        //
        memset(&reply_addr, 0, sizeof(reply_addr));
        reply_addr.sin_family = AF_INET;
        reply_addr.sin_addr.s_addr = addr_from[i].sin_addr.s_addr;
        reply_addr.sin_port = addr_from[i].sin_port;
        enable_thread = 1;                                // initialise thread to active
        active_thread = 1;
        //
        // create outgoing packet thread
        //
        if(pthread_create(&thread, NULL, OutgoingDDCIQ, NULL) < 0)
        {
          perror("pthread_create");
          return EXIT_FAILURE;
        }
        pthread_detach(thread);
        break;
    }// end switch (packet type)

//
// now do any "post packet" processing
//
  } //while(1)
  close(socket_cmddata);                          // close incoming data socket

  return EXIT_SUCCESS;
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
	int DMAReadfile_fd = -1;											// DMA read file device
	uint32_t RegisterValue;


//
// variables for outgoing UDP frame
//
  struct iovec iovecinst;                                 // instance of iovec
  struct msghdr datagram;
  uint8_t UDPBuffer[VDDCPACKETSIZE];                      // DDC frame buffer
  uint32_t SequenceCounter = 0;                           // UDP sequence count
  uint32_t IQCount;                                       // counter of words to read
//
// initialise. Create memory buffers and open DMA file devices
//
  printf("starting up outgoing thread\n");
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
  // initialise outgoing DDC packet
  // THIS STILL NEEDS TO BE CHANGED FOR DESTINATION PORT NUMBER!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  //
  memset(&iovecinst, 0, sizeof(struct iovec));
  memset(&datagram, 0, sizeof(datagram));
  iovecinst.iov_base = UDPBuffer;
  iovecinst.iov_len = VDDCPACKETSIZE;
  datagram.msg_iov = &iovecinst;
  datagram.msg_iovlen = 1;
  datagram.msg_name = &reply_addr;                   // MAC addr & port to send to
  datagram.msg_namelen = sizeof(reply_addr);

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
// write 3 to GPIO to enable FIFO writes
//
	RegisterWrite(0xA000, 3);				// write to the GPIO register
	printf("GPIO Register written with value=3, enabling writes\n");


//
// thread loop. runs continuously until commanded by main loop to exit
// for now: add 1 RX data + mic data at 48KHz sample rate. Mic data is constant zero.
// while there is enough I/Q data, make outgoing packets;
// when not enough data, read more.
//
  while(!InitError)
  {
    if(!enable_thread) break;                                     // exit thread if commanded
		
    //
    // while there is enough I/Q data, make DDC Packets
    //
    while((IQHeadPtr - IQReadPtr)>VIQBYTESPERFRAME)
    {
      *(uint32_t *)UDPBuffer = htonl(SequenceCounter++);        // add sequence count
      memset(UDPBuffer+4, 0,8);                                 // clear the timestamp data
      *(uint16_t *)(UDPBuffer+12) = 24;                         // bits per sample
      *(uint32_t *)(UDPBuffer+14) = VIQSAMPLESPERFRAME;         // I/Q samples for ths frame
      //
      // now add I/Q data & send outgoing packet
      //
      memcpy(UDPBuffer + 16, IQReadPtr, VIQBYTESPERFRAME);
      IQReadPtr += VIQBYTESPERFRAME;
      sendmsg(socket_cmddata, &datagram, 0);
    }
    //
    // now bring in more data via DMA
    // first copy any residue to the start of the buffer (before the DMA point)
//
		ResidueBytes = IQHeadPtr- IQReadPtr;
		printf("Residue = %d bytes\n",ResidueBytes);
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
		printf("read: depth = %d\n", Depth);
		while(Depth < 512)			// 512 locations = 4K bytes
		{
			usleep(1000);								// 1ms wait
			Depth = RegisterRead(0x9000);				// read the user access register
			printf("read: depth = %d\n", Depth);
		}

		printf("DMA read %d bytes from destination to base\n", VDMATRANSFERSIZE);
		DMAReadFromFPGA(DMAReadfile_fd, IQBasePtr, VDMATRANSFERSIZE, AXIBaseAddress);
		IQHeadPtr = IQBasePtr + VDMATRANSFERSIZE;
  }     // end of while(!InitError) loop

//
// tidy shutdown of the thread
//
  active_thread = 0;        // signal that thread has closed
	close(DMAReadfile_fd);
  free(IQReadBuffer);
  return NULL;
}

