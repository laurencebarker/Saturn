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
#include <sys/mman.h>
#include <sys/time.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <net/if.h>

#include "hwaccess.h"                     // access to PCIe read & write
#include "saturnregisters.h"              // register I/O for Saturn


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
  int i, j, size;
  pthread_t thread;

//
// part written discovery reply packet
//
  uint8_t reply[11] = {0xef, 0xfe, 2, 0, 0, 0, 0, 0, 0, SDRSWVERSION, SDRBOARDID};
  uint8_t id[4] = {0xef, 0xfe, 1, 6};                                                   // don't think this is needed here
  uint32_t code;                                                        // command word from PC app
  struct ifreq hwaddr;                                                  // holds this device MAC address
  struct sockaddr_in addr_ep2, addr_from[10];                           // holds MAC address of source of incoming messages
  uint8_t buffer[8][VMETISFRAMESIZE];                                   // 8 outgoing buffers
  struct iovec iovec[8][1];                                             // iovcnt buffer - 1 for each outgoing buffer
  struct mmsghdr datagram[8];                                           // multiple incoming message header
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
  


  /* keep until code fully documented
  sts = mmap(NULL, sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0x40000000);
  cfg = mmap(NULL, sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0x40001000);
  alex = mmap(NULL, sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0x40002000);
  tx_mux = mmap(NULL, sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0x40003000);
  dac_data = mmap(NULL, sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0x40006000);
  adc_data = mmap(NULL, sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0x40007000);
  tx_data = mmap(NULL, 4*sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0x4000c000);
  xadc = mmap(NULL, 16*sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0x40020000);

  for(i = 0; i < 5; ++i)
  {
    rx_data[i] = mmap(NULL, 2*sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0x40010000 + i * 0x2000);
  }
  */


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
    memset(iovec, 0, sizeof(iovec));
    memset(datagram, 0, sizeof(datagram));

    for(i = 0; i < 8; ++i)
    {
      memcpy(buffer[i], id, 4);                         // don't know why we do this for incoming messages
      iovec[i][0].iov_base = buffer[i];                 // set buffer for incoming message number i
      iovec[i][0].iov_len = 1032;
      datagram[i].msg_hdr.msg_iov = iovec[i];
      datagram[i].msg_hdr.msg_iovlen = 1;
      datagram[i].msg_hdr.msg_name = &addr_from[i];
      datagram[i].msg_hdr.msg_namelen = sizeof(addr_from[i]);
    }

    ts.tv_sec = 0;                                          // 1ms timeout
    ts.tv_nsec = 1000000;

    size = recvmmsg(sock_ep2, datagram, 8, 0, &ts);         // get a batch of 8 messages
    if(size < 0 && errno != EAGAIN)
    {
      perror("recvfrom");
      return EXIT_FAILURE;
    }

    for(i = 0; i < size; ++i)                               // loop through incoming messages
    {
      memcpy(&code, buffer[i], 4);                          // copy the Metis frame identifier
      switch(code)
      {
        // PC to Metis data frame, EP2 data. C&C, TX I/Q, spkr
        // this is "normal SDR traffic"
        case 0x0201feef:
          if(!tx_mux_data)
          {
            while(*tx_cntr > 3844) usleep(1000);            // sleep if not enough data available
            if(*tx_cntr == 0) for(j = 0; j < 2520; ++j) *tx_data = 0;   // FIFO under-run??
            if((*gpio_out & 1) | (*gpio_in & 1))                        // if TX
            {
              for(j = 0; j < 504; j += 8)                               // write TX I/Q to FIFO
              {
                *tx_data = tx_eer_data ? *(uint32_t *)(buffer[i] + 16 + j) : 0;     // 1st USB frame
                *tx_data = *(uint32_t *)(buffer[i] + 20 + j);
              }
              for(j = 0; j < 504; j += 8)
              {
                *tx_data = tx_eer_data ? *(uint32_t *)(buffer[i] + 528 + j) : 0;    // 2nd USB frame
                *tx_data = *(uint32_t *)(buffer[i] + 532 + j);
              }
            }
            else
            {
              for(j = 0; j < 126; ++j) *tx_data = 0;                    // no TX so write zeros
            }
          }
          if(i2c_codec)                                                 // speaker data if Codec attached
          {
            while(*dac_cntr > 898) usleep(1000);                        // sleep if not enough space yet
            if(*dac_cntr == 0) for(j = 0; j < 504; ++j) *dac_data = 0;
            for(j = 0; j < 504; j += 8) *dac_data = *(uint32_t *)(buffer[i] + 16 + j);
            for(j = 0; j < 504; j += 8) *dac_data = *(uint32_t *)(buffer[i] + 528 + j);
          }
          process_incoming_CandC(buffer[i] + 11);                   // process 1st C&C frame
          process_incoming_CandC(buffer[i] + 523);                  // process 2nd C&C frame
          break;


        // Metis "discover request" from PC
        // send message back to MAC address and port of originating request message
        case 0x0002feef:
          reply[2] = 2 + active_thread;                             // response 2 if not active, 3 if running
          memset(buffer[i], 0, 60);
          memcpy(buffer[i], reply, 11);
          sendto(sock_ep2, buffer[i], 60, 0, (struct sockaddr *)&addr_from[i], sizeof(addr_from[i]));
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
          rx_sync_data = 0;

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
      }
    }               // end switch (packet type)

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
            SetP1SampleRate((ESampleRate)(C1 & 3));
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
// this runs as its own thread to send outgoing data
// thread initiated after a Metis "Start" command
// will be instructed to stop & exit by main loop setting enable_thread to 0
// this code signals thread terminated by setting active_thread = 0
//
void *SendOutgoingPacketData(void *arg)
{
  int i, j, k, m, n, size, rate_counter;
  int data_offset, header_offset;
  uint32_t counter;
  int32_t value;
  uint16_t audio[512];
  uint8_t data0[4096];
  uint8_t data1[4096];
  uint8_t data2[4096];
  uint8_t data3[4096];
  uint8_t data4[4096];
  uint8_t buffer[25 * 1032];
  uint8_t *pointer;
  struct iovec iovec[25][1];
  struct mmsghdr datagram[25];
  uint8_t id[4] = {0xef, 0xfe, 1, 6};
  //
  // 5 USB data headers with outgoing C&C data
  //
  uint8_t header[40] =
  {
    127, 127, 127, 0, 0, 33, 17, 21,
    127, 127, 127, 8, 0, 0, 0, 0,
    127, 127, 127, 16, 0, 0, 0, 0,
    127, 127, 127, 24, 0, 0, 0, 0,
    127, 127, 127, 32, 66, 66, 66, 66
  };

  memset(audio, 0, sizeof(audio));
  memset(iovec, 0, sizeof(iovec));
  memset(datagram, 0, sizeof(datagram));

  //
  // initialise 25 outgoing metis frames
  //
  for(i = 0; i < 25; ++i)
  {
    memcpy(buffer + i * VMETISFRAMESIZE, id, 4);
    iovec[i][0].iov_base = buffer + i * VMETISFRAMESIZE;
    iovec[i][0].iov_len = VMETISFRAMESIZE;
    datagram[i].msg_hdr.msg_iov = iovec[i];
    datagram[i].msg_hdr.msg_iovlen = 1;
    datagram[i].msg_hdr.msg_name = &addr_ep6;                   // MAC addr & port to send to
    datagram[i].msg_hdr.msg_namelen = sizeof(addr_ep6);
  }

  header_offset = 0;
  counter = 0;
  rate_counter = 1 << rate;                             // 1=48KHz; 2=96KHz; 4=192KHz; 8=384KHz
  k = 0;

//
// thread loop. runs continuously until commanded by main loop to exit
//
  while(1)
  {
    if(!enable_thread) break;                           // exit thread if commanded

    size = receivers * 6 + 2;                           // total bytes per sample
    n = 504 / size;                                     // samples per USB frame
    m = 256 / n;                                        // ???

    //
    // reset FIFOs if overflow has occurred
    //
    if((i2c_codec && *adc_cntr >= 1024) || *rx_cntr >= 2048)
    {
      if(i2c_codec)
      {
        /* reset codec ADC fifo */
        *rx_rst |= 2;
        *rx_rst &= ~2;
      }

      /* reset rx fifo */
      *rx_rst |= 1;
      *rx_rst &= ~1;
    }

    //
    // sleep until there is enough data
    //
    while(*rx_cntr < m * n * 4) usleep(1000);

    if(i2c_codec && --rate_counter == 0)
    {
      for(i = 0; i < m * n * 2; ++i)                        // read mic samples into a buffer
      {
        audio[i] = *adc_data;
      }
      rate_counter = 1 << rate;
      k = 0;
    }

    for(i = 0; i < m * n * 16; i += 8)
    {
      *(uint64_t *)(data0 + i) = *rx_data[0];
      *(uint64_t *)(data1 + i) = *rx_data[1];
      *(uint64_t *)(data2 + i) = *rx_data[2];
      *(uint64_t *)(data3 + i) = *rx_data[3];
      *(uint64_t *)(data4 + i) = *rx_data[4];
    }

    data_offset = 0;
    for(i = 0; i < m; ++i)
    {
      *(uint32_t *)(buffer + i * 1032 + 4) = htonl(counter);
      ++counter;
    }

    for(i = 0; i < m * 2; ++i)
    {
      pointer = buffer + i * 516 - i % 2 * 4 + 8;
      memcpy(pointer, header + header_offset, 8);
      pointer[3] |= (*gpio_in & 7) | cw_ptt;                        // outgoing C&C: C0 byte
      if(header_offset == 8)
      {
        value = xadc[152] >> 3;
        pointer[6] = (value >> 8) & 0xff;                           // Alex/Atlas forward power
        pointer[7] = value & 0xff;
      }
      else if(header_offset == 16)
      {
        value = xadc[144] >> 3;
        pointer[4] = (value >> 8) & 0xff;                           // Alex/Atlas reverse power
        pointer[5] = value & 0xff;
        value = xadc[145] >> 3;                                     // AIN3
        pointer[6] = (value >> 8) & 0xff;
        pointer[7] = value & 0xff;
      }
      else if(header_offset == 24)
      {
        value = xadc[153] >> 3;
        pointer[4] = (value >> 8) & 0xff;                           // AIN4
        pointer[5] = value & 0xff;
      }
      header_offset = header_offset >= 32 ? 0 : header_offset + 8;

      pointer += 8;
      memset(pointer, 0, 504);
      for(j = 0; j < n; ++j)
      {
        memcpy(pointer, data0 + data_offset, 6);
        if(size > 8)
        {
          memcpy(pointer + 6, data1 + data_offset, 6);
        }
#ifndef THETIS
        if(size > 14)
        {
          memcpy(pointer + 12, data3 + data_offset, 6);
        }
        if(size > 20)
        {
          memcpy(pointer + 18, data4 + data_offset, 6);
        }
#else
        if(size > 14)
        {
          memcpy(pointer + 12, data2 + data_offset, 6);
        }
        if(size > 20)
        {
          memcpy(pointer + 18, data3 + data_offset, 6);
        }
        if(size > 26)
        {
          memcpy(pointer + 24, data4 + data_offset, 6);
        }
#endif
        data_offset += 8;
        pointer += size;
        if(i2c_codec) memcpy(pointer - 2, &audio[(k++) >> rate], 2);
      }
    }
    //
    // send outgoing packet
    //
    sendmmsg(sock_ep2, datagram, m, 0);
  }     // end of while(1) loop

  active_thread = 0;        // signal that thread has closed

  return NULL;
}

