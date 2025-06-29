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
// p1app.c:
//
// Protocol1 is defined by "Metis - How it works" V1.33
// and USB protocol V1.58
// Convention is data goes to 3 endpoints:
// EP2: data from PC to SDR
// EP4: baseband data from SDR to PC
// EP6: I/Q data from SDR to PC
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

#include "../common/saturntypes.h"
#include "../common/hwaccess.h"                     // access to PCIe read & write
#include "../common/saturnregisters.h"              // register I/O for Saturn
#include "../common/codecwrite.h"                   // codec register I/O for Saturn
#include "../common/version.h"                      // version I/O for Saturn


int receivers = 1;                          // number of requested DDC (1-8)
int rate = 0;                               // reqd sample rate (00=48KHz .. 11 = 384KHz)


int sock_ep2;                               // socket for PC to SDR data
struct sockaddr_in addr_ep6;                // destination address for outgoing data

int enable_thread = 0;                      // true if outgoing data thread enabled
int active_thread = 0;                      // true if outgoing thread is running

void process_incoming_CandC(uint8_t *frame);
void *SendOutgoingPacketData(void *arg);


#define SDRBOARDID 1                    // Hermes
#define SDRSWVERSION 1                  // version of this software
#define VMETISFRAMESIZE 1032            // each Metis Frame

//
// main program. Initialise, then handle incoming data
// has a loop that reads & processes incoming "EP2" packets
// each packet is 2 USB frames as described in "Metis - How it works" V1.33
//
int main(void)
{
  int i, size;
  pthread_t thread;

//
// part written discovery reply packet
//
  uint8_t reply[11] = {0xef, 0xfe, 2, 0, 0, 0, 0, 0, 0, SDRSWVERSION, SDRBOARDID};
  uint8_t id[4] = {0xef, 0xfe, 1, 6};                                                   // don't think this is needed here
  uint32_t code;                                                        // command word from PC app
  struct ifreq hwaddr;                                                  // holds this device MAC address
  struct sockaddr_in addr_ep2, addr_from[10];                           // holds MAC address of source of incoming messages
  uint8_t UDPInBuffer[VMETISFRAMESIZE];                                   // 8 outgoing buffers
  struct iovec iovecinst;                                             // iovcnt buffer - 1 for each outgoing buffer
  struct msghdr datagram;                                           // multiple incoming message header
  struct timeval tv;
  struct timespec ts;
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
  if((sock_ep2 = socket(AF_INET, SOCK_DGRAM, 0)) < 0)
  {
    perror("socket");
    return EXIT_FAILURE;
  }

  //
  // get this device MAC address
  //
  memset(&hwaddr, 0, sizeof(hwaddr));
  strncpy(hwaddr.ifr_name, "eth0", IFNAMSIZ - 1);
  ioctl(sock_ep2, SIOCGIFHWADDR, &hwaddr);
  for(i = 0; i < 6; ++i) reply[i + 3] = hwaddr.ifr_addr.sa_data[i];         // copy MAC to reply message

  setsockopt(sock_ep2, SOL_SOCKET, SO_REUSEADDR, (void *)&yes , sizeof(yes));

  //
  // set 1ms timeout
  //
  tv.tv_sec = 0;
  tv.tv_usec = 1000;
  setsockopt(sock_ep2, SOL_SOCKET, SO_RCVTIMEO, (void *)&tv , sizeof(tv));

  //
  // bind application to port 1024
  //
  memset(&addr_ep2, 0, sizeof(addr_ep2));
  addr_ep2.sin_family = AF_INET;
  addr_ep2.sin_addr.s_addr = htonl(INADDR_ANY);
  addr_ep2.sin_port = htons(1024);

  if(bind(sock_ep2, (struct sockaddr *)&addr_ep2, sizeof(addr_ep2)) < 0)
  {
    perror("bind");
    return EXIT_FAILURE;
  }


  //
  // now main processing loop. Process received Metis packets
  //
  while(1)
  {
    memset(&iovecinst, 0, sizeof(struct iovec));
    memset(&datagram, 0, sizeof(datagram));

    memcpy(UDPInBuffer, id, 4);                         // don't know why we do this for incoming messages
    iovecinst.iov_base = &UDPInBuffer;                  // set buffer for incoming message number i
    iovecinst.iov_len = 1032;
    datagram.msg_iov = &iovecinst;
    datagram.msg_iovlen = 1;
    datagram.msg_name = &addr_from[i];
    datagram.msg_namelen = sizeof(addr_from[i]);

    size = recvmsg(sock_ep2, &datagram, 0);         // get a batch of 8 messages
    if(size < 0 && errno != EAGAIN)
    {
      perror("recvfrom");
      return EXIT_FAILURE;
    }

    memcpy(&code, &UDPInBuffer, 4);                          // copy the Metis frame identifier
    switch(code)
    {
      // PC to Metis data frame, EP2 data. C&C, TX I/Q, spkr
      // this is "normal SDR traffic"
      case 0x0201feef:
        printf("RX metis frame\n");


        break;


      // Metis "discover request" from PC
      // send message back to MAC address and port of originating request message
      case 0x0002feef:
        printf("received metis discover request frame\n");
        reply[2] = 2 + active_thread;                             // response 2 if not active, 3 if running
        memset(&UDPInBuffer, 0, 60);
        memcpy(&UDPInBuffer, reply, 11);
        sendto(sock_ep2, &UDPInBuffer, 60, 0, (struct sockaddr *)&addr_from[i], sizeof(addr_from[i]));
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
        memset(&addr_ep6, 0, sizeof(addr_ep6));
        addr_ep6.sin_family = AF_INET;
        addr_ep6.sin_addr.s_addr = addr_from[i].sin_addr.s_addr;
        addr_ep6.sin_port = addr_from[i].sin_port;
        enable_thread = 1;                                // initialise thread to active
        active_thread = 1;
        //
        // create outgoing packet thread
        //
        if(pthread_create(&thread, NULL, SendOutgoingPacketData, NULL) < 0)
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
  close(sock_ep2);                          // close incoming data socket

  return EXIT_SUCCESS;
}




//
// process incoming 4 byte C&C data from PC app
// called from main program loop above
//
void process_incoming_CandC(uint8_t *frame)
{
    uint16_t data16;
    uint32_t data32;
    uint8_t C0, C1, C2, C3, C4;

    C0 = frame[0];                                    // 1st C&C sets type
    C1 = frame[1];                                    // C&C byte
    C2 = frame[2];                                    // C&C byte
    C3 = frame[3];                                    // C&C byte
    C4 = frame[4];                                    // C&C byte
    data32 = ntohl(*(uint32_t*)(frame + 1));          // C1-C4 as 32 bits

//
// check MOX
//
    SetMOX((bool)(C0&1));                              // set MOX bit

//
// now set the C0 dependent settings
//
    switch(C0)
    {
    //C0=0b0000000x:
    // Atlas bus controls; DDC sample rate; TX mode; open collector outputs; 
    // ADC dither& random; Alex atten; Alex RX ant, RX out, TX ant; Duplex on / off; 
    // DDC count; time stamp on / off
        case 0:
        case 1:
            SetP1SampleRate((ESampleRate)((C1 & 3)+1), ((C4 >> 3) & 7)+1);
            // skip Atlas bus controls (10MHz source, clock source, config, mic)
            SetClassEPA((bool)(C2 & 1));
            SetOpenCollectorOutputs(C2 >> 1);
            SetAlexCoarseAttenuator(C3 & 3);
            SetADCOptions(eADC1, (bool)((C3>>2)&1), (bool)((C3 >> 3) & 1), (bool)((C3 >> 4) & 1));
            SetAlexRXAnt(C3 >> 6);
            SetAlexRXOut((bool)(C3 >> 7));
            SetAlexTXAnt(C4 & 3);
            SetDuplex((bool)((C4 >> 2) & 1));
            SetNumP1DDC((C4 >> 3) & 7);
            EnablePPSStamp((bool)((C4 >> 6) & 1));
            // skip mercury frequency
            break;


        //C0=0b0000001x:
        // TX frequency (Hz)
        case 2:
        case 3:
            SetDUCFrequency(0, data32, false);
            break;


        //C0=0b0000010x:
        // DDC0 frequency (Hz)
        case 4:
        case 5:
            SetDDCFrequency(0, data32, false);
            break;


        //C0=0b0000011x:
        // DDC1 frequency (Hz)
        case 6:
        case 7:
            SetDDCFrequency(1, data32, false);
            break;


        //C0=0b0000100x:
        // DDC2 frequency (Hz)
        case 8:
        case 9:
            SetDDCFrequency(2, data32, false);
            break;


        //C0=0b0000101x:
        // DDC3 frequency (Hz)
        case 10:
        case 11:
            SetDDCFrequency(3, data32, false);
            break;


        //C0=0b0000110x:
        // DDC4 frequency (Hz)
        case 12:
        case 13:
            SetDDCFrequency(4, data32, false);
            break;


        //C0=0b0000111x:
        // DDC5 frequency (Hz)
        case 14:
        case 15:
            SetDDCFrequency(5, data32, false);
            break;


        //C0=0b0001000x:
        // DDC6 frequency (Hz)
        case 16:
        case 17:
            SetDDCFrequency(6, data32, false);
            break;


        //C0=0b0001001x:
        // TX drive level; mic boost; mic/line in; Apollo controls; manual / auto filter select; 
        // Alex RX1 filters; Alex disable T / R relay; Alex TX filters; set apollo bits
    case 18:
    case 19:
        SetTXDriveLevel(0, C1);
        SetMicBoost((bool)(C2 & 1));
        SetMicLineInput((bool)((C2 >> 1) & 1));
        SetApolloBits((bool)((C2 >> 2) & 1), (bool)((C2 >> 3) & 1), (bool)((C2 >> 4) & 1));
        SelectFilterBoard((bool)((C2 >> 5) & 1));
        SetAlexRXFilters(true, C3 & 0b01111111);
        DisableAlexTRRelay((bool)((C3 >> 7) & 1));
        SetAlexTXFilters(C4);
        break;
    //C0=0b0001010x:
    // mic tip/ring select; mic bias; mic PTT; codec line in gain; puresignal enable; ADC1 atten;
    case 20:
    case 21:
        // check P1 code: do I need RX1-4 preamp bits?
        SetOrionMicOptions((bool)((C1 >> 4) & 1), (bool)((C1 >> 5) & 1), (bool)((C1 >> 6) & 1));
        SetCodecLineInGain(C2 & 0b00011111);
        // Check P1 code: do I need C2 bits 7-5?
        // check P1 code: do I need C3 bits?
        SetADCAttenuator(eADC1, C4&0b00011111, (bool)((C4 >> 5) & 1));
        break;


    //C0=0b0001011x:
    // ADC2 atten; ADC3 atten; CW keys reversed; keyer speed, keyer mode, keyer weight, keyer spacing
    case 22:
    case 23:
        SetADCAttenuator(eADC2, C1 & 0b00011111, (bool)((C1 >> 5) & 1));
        // ignore ADC3 data
        SetCWKeyerReversed((bool)((C2 >> 6) & 1));
        SetCWKeyerSpeed(C3 & 0b00111111);
        SetCWKeyerMode((C3 >> 6) & 3);
        SetCWKeyerWeight(C4 & 0b01111111);              // what is keyer weight
        SetCWKeyerSpacing((bool)((C4 >> 7) & 1));
    case 24:
    case 25:
    case 26:
    case 27:
        break;


    //C0=0b0001110x:
    // ADC assignment; ADC atten during TX
    case 28:
    case 29:
        SetDDCADC(0, C1 & 3);
        SetDDCADC(1, (C1 >> 2) & 3);
        SetDDCADC(2, (C1 >> 4) & 3);
        SetDDCADC(3, (C1 >> 6) & 3);
        SetDDCADC(5, C2 & 3);
        SetDDCADC(6, (C2 >> 2) & 3);
        SetDDCADC(7, (C2 >> 4) & 3);
        SetADCAttenDuringTX(C3&0b00011111);
      break;


    //C0=0b0001111x:
    // CW enable; CW sidetone volume; CW PTT delay
    case 30:
    case 31:
        EnableCW((bool)(C1 & 1));
        SetCWSidetoneVol(C2);
        SetCWPTTDelay(C3);
        break;


    //C0=0b0010000x:
    // CW hang time, CW sidetone frequency;
    case 32:
    case 33:
        data16 = (C1 << 2) | (C2 & 0b00000011);
        SetCWHangTime(data16);
        data16 = (C3 << 4) | (C4 & 0b00001111);
        SetCWSidetoneFrequency(data16);
        break;


      //C0=0b0010001x:
      // PWM min, max pulse width
    case 34:
    case 35:
        data16 = (C1 << 2) | (C2 & 0b00000011);
        SetMinPWMWidth(data16);
        data16 = (C3 << 2) | (C4 & 0b00000011);
        SetMaxPWMWidth(data16);
        break;


        //C0=0b0010010x:
        // RX2 filters; transverter enable; puresignal enable
    case 36:
    case 37:
        SetAlexRXFilters(false, C1 & 0b01111111);
        SetRX2GroundDuringTX((bool)((C1 >> 7) & 1));
        SetXvtrEnable((bool)(C2 & 1));
        // there's a puresignal bit here too somewhere check paper docs
        break;
  }
}








//
// global holding the current step of C&C data. Each new USB frame updates this.
//
uint32_t OutgoingCandCStep;                         // 0-1-2-3-4 sequence for C&C data
#define VDMABUFFERSIZE 32768									      // memory buffer to reserve
#define VALIGNMENT 4096                             // buffer alignment
#define VBASE 0x1000									              // DMA start at 4K into buffer
#define VMETISFRAMESIZE 1032
#define VBASE 0x1000                                // offset into I/Q buffer for DMA to start
#define VUSBSAMPLESIZE 504                          // useful data per USB Frame
#define VDMATRANSFERSIZE 4096                       // read 4K at a time
#define AXIBaseAddress 0x18000									    // address of StreamRead/Writer IP (Litefury only!)
#define VIQBYTESPERMETISFRAME 228                   // 19 sets of (same) I/Q per USB, 2USB per metis

  //
  // 5 USB data headers with outgoing C&C data
  //
  uint8_t USBCandC[40] =
  {
    0x7F, 0x7F, 0x7F, 0, 0, 33, 17, 21,
    0x7F, 0x7F, 0x7F, 8, 0, 0, 0, 0,
    0x7F, 0x7F, 0x7F, 16, 0, 0, 0, 0,
    0x7F, 0x7F, 0x7F, 24, 0, 0, 0, 0,
    0x7F, 0x7F, 0x7F, 32, 66, 66, 66, 66
  };



//
// AddOutgoingC&CBytes(unsigned char* Ptr, uint32_t CandCSequence);
//
// add the 8 C&C bytes for one USB frame beginning at the address pointed. 
// the C&C sequence is given by the other parameter, which is updated by this
//
void AddOutgoingCandCBytes(uint8_t* Ptr)
{
  memcpy(Ptr, USBCandC+8*OutgoingCandCStep, 8);
  switch(OutgoingCandCStep)
  {
    case 0:
      OutgoingCandCStep++;
      break;
    case 1:
      OutgoingCandCStep++;
      break;
    case 2:
      OutgoingCandCStep++;
      break;
    case 3:
      OutgoingCandCStep++;
      break;
    case 4:
    default:
      OutgoingCandCStep = 0;
      break;
  }
}



//
// this runs as its own thread to send outgoing data
// thread initiated after a Metis "Start" command
// will be instructed to stop & exit by main loop setting enable_thread to 0
// this code signals thread terminated by setting active_thread = 0
//
void *SendOutgoingPacketData(void *arg)
{
//
// memory buffers
//
  uint8_t* IQReadBuffer = NULL;											// data for DMA read from DDC
	uint32_t IQBufferSize = VDMABUFFERSIZE;
  uint8_t* MicBuffer = NULL;											    // data for DMA read from Mic
	uint32_t MicBufferSize = VDMABUFFERSIZE;
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
  uint8_t UDPBuffer[VMETISFRAMESIZE];                     // Metis frame buffer
  uint8_t metisid[4] = {0xef, 0xfe, 1, 6};                // Metis frame identifier
  uint32_t SequenceCounter = 0;                           // UDP sequence count
  uint32_t USBFrame;
  uint8_t *USBFramePtr;                                    // write address into o/p frame buffer
  uint32_t IQCount;                                       // counter of words to read
//
// initialise. Create memory buffers and open DMA file devices
//
  OutgoingCandCStep = 0;                                  // initialise C&C output
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


	posix_memalign((void **)&MicBuffer, VALIGNMENT, MicBufferSize);
	if(!MicBuffer)
	{
		printf("Mic sample buffer allocation failed\n");
		InitError = true;
	}
  memset(MicBuffer, 0, MicBufferSize);

//
// open DMA device driver
//
	DMAReadfile_fd = open("/dev/xdma0_c2h_0", O_RDONLY);
	if(DMAReadfile_fd < 0)
	{
		printf("XDMA read device open failed\n");
		InitError = true;
	}

  //
  // initialise outgoing metis frame
  //
  memset(&iovecinst, 0, sizeof(struct iovec));
  memset(&datagram, 0, sizeof(datagram));
  memcpy(UDPBuffer, metisid, 4);
  iovecinst.iov_base = UDPBuffer;
  iovecinst.iov_len = VMETISFRAMESIZE;
  datagram.msg_iov = &iovecinst;
  datagram.msg_iovlen = 1;
  datagram.msg_name = &addr_ep6;                   // MAC addr & port to send to
  datagram.msg_namelen = sizeof(addr_ep6);

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
    // while there is enough I/Q data, make Metis frames
    //
    while((IQHeadPtr - IQReadPtr)>VIQBYTESPERMETISFRAME)
    {
      *(uint32_t *)(UDPBuffer  + 4) = htonl(SequenceCounter++);     // add sequence count
      for(USBFrame=0; USBFrame < 2; USBFrame++)
      {
        USBFramePtr = UDPBuffer + 8 + 512*USBFrame;                 // point to start of USB frame
        AddOutgoingCandCBytes(USBFramePtr);
        USBFramePtr += 8;
        //
        // now add I/Q and (null) microphone audio data.
        // the board is pretending to be a Hermes, so need to offer back 4 receivers worth of data
        //
        for(IQCount = 0; IQCount < 19; IQCount++)
        {
          memcpy(USBFramePtr, IQReadPtr, 6);                        // copy one set of I/Q samples
          USBFramePtr+= 6;
          memcpy(USBFramePtr, IQReadPtr, 6);                        // copy same set of I/Q samples
          USBFramePtr+= 6;
          memcpy(USBFramePtr, IQReadPtr, 6);                        // copy same set of I/Q samples
          USBFramePtr+= 6;
          memcpy(USBFramePtr, IQReadPtr, 6);                        // copy same set of I/Q samples
          USBFramePtr+= 6;
          *USBFramePtr++ = 0;                                       // add 2 zero bytes for mic
          *USBFramePtr++ = 0;
          IQReadPtr += 6;
        }
        memset(USBFramePtr, 0, 10);                                 // add 10 padding bytes
        USBFramePtr += 10;
      }
      //
      // send outgoing packet
      //
      sendmsg(sock_ep2, &datagram, 0);
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
  free(MicBuffer);
  return NULL;
}

