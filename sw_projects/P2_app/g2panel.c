/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// g2panel.c:
//
// interface G2 front panel using GPIO and I2C
//
//////////////////////////////////////////////////////////////

#include "g2panel.h"
#include "threaddata.h"
#include <stdint.h>
#include "../common/saturntypes.h"
#include <errno.h>
#include <stdlib.h>
#include <stddef.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <sys/time.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <pthread.h>
#include <gpiod.h>
#include <pthread.h>

#include "../common/saturnregisters.h"
#include "../common/saturndrivers.h"
#include "../common/hwaccess.h"
#include "../common/debugaids.h"
#include "cathandler.h"
#include "i2cdriver.h"


bool G2PanelControlled = false;
extern int i2c_fd;                                  // file reference
static struct gpiod_chip *chip = NULL;
char* gpio_device = NULL;
char *consumer = "p2app";
struct gpiod_line *VFO1;                            // declare GPIO for VFO
struct gpiod_line *VFO2;
pthread_t VFOEncoderThread;                         // thread looks for encoder edge events
pthread_t G2PanelTickThread;                        // thread with periodic
uint16_t GDeltaCount;                    // count stored since last retrieved
struct timespec ts = {1, 0};
bool G2PanelActive = false;                         // true while panel active and threads should run
bool EncodersInitialised = false;                   // true after 1st scan


#define VNUMGPIOPUSHBUTTONS 4
#define VNUMMCPPUSHBUTTONS 16
#define VNUMBUTTONS VNUMGPIOPUSHBUTTONS+VNUMMCPPUSHBUTTONS
#define VNUMENCODERS 8
#define VNUMGPIO 2*VNUMENCODERS +  VNUMGPIOPUSHBUTTONS
//
// IO pins for encoder inputs then 4 pushbutton inputs
//
uint32_t PBIOPins[VNUMGPIO] = {20, 26, 6, 5, 4, 21, 7, 9, 
                               16, 19, 10, 11, 25, 8, 12, 13,
                               22, 27, 23, 24};
struct gpiod_line_bulk PBInLines;
struct gpiod_line_request_config config = {"p2app", GPIOD_LINE_REQUEST_DIRECTION_INPUT, 0};
int32_t IOPinValues[VNUMGPIO] = {-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1};

//
// pushbutton inputs: each has a byte, with new tick added at LSB. Supports simple debounce.
//
uint8_t PBPinShifts [VNUMBUTTONS] =    {0xFF, 0xFF, 0xFF, 0xFF,
                                        0xFF, 0xFF, 0xFF, 0xFF, 
                                        0xFF, 0xFF, 0xFF, 0xFF, 
                                        0xFF, 0xFF, 0xFF, 0xFF,
                                        0xFF, 0xFF, 0xFF, 0xFF};

uint8_t EncoderStates[VNUMENCODERS];            // current and previous 2 bit state
int8_t EncoderCounts[VNUMENCODERS];            // number of steps since last read

// GPIO pins used for G2 panel:
// note switch inputs need pullups but encoders don't

// GPIO2    SDA for I2C
// GPIO3    SCK for I2C
// GPIO15   INTA for MNCP23017

// GPIO17   VFO encoder
// GPIO18   VFO encoder

// GPIO20   ENC1 1A
// GPIO26   ENC1 1B
// GPIO6    ENC1 2A
// GPIO5    ENC1 2B
// GPIO22   ENC1 SW

// GPIO4    ENC3 1A
// GPIO21   ENC3 1B
// GPIO7    ENC3 2A
// GPIO9    ENC3 2B
// GPIO27   ENC3 SW

// GPIO16   ENC5 1A
// GPIO19   ENC5 1B
// GPIO10   ENC5 2A
// GPIO11   ENC5 2B
// GPIO23   ENC5 SW

// GPIO25   ENC7 1A
// GPIO8    ENC7 1B
// GPIO12   ENC7 2A
// GPIO13   ENC7 2B
// GPIO24   ENC7 SW

// GPIO14   unused

//
// MCP23017 IO pins:
// GPA0   SW6
// GPA1   SW7
// GPA2   SW8
// GPA3   SW9
// GPA4   SW10
// GPA5   SW11
// GPA6   SW12
// GPA7   SW13
// GPB0   SW15
// GPB1   SW16
// GPB2   SW17
// GPB3   SW18
// GPB4   SW19
// GPB5   SW20
// GPB6   SW21
// GPB7   SW22


#define VOPTENCODERDIVISOR 1                        // only declare every n-th event
                                                    // (1 OK for optical high res)
//
// read the optical encoder. Return the number of steps turned since last called.
// read back the count since last asked, then zero it for the next time
// if Divisor is above 1: leave behind the residue
//
int8_t ReadOpticalEncoder(void)
{
  int8_t Result;

  Result = GDeltaCount / VOPTENCODERDIVISOR;                         // get count value
  GDeltaCount = GDeltaCount % VOPTENCODERDIVISOR;                    // remaining residue for next time
  return Result;
}




//
// VFO encoder pin interrupt handler
// this executes as a thread; it waits for an event on a VFO encoder pin
// for a high res encoder at just one interrupt per pulse - use int on one edge and use the sense of the other to set direction.
//
void VFOEventHandler(void *arg)
{
    int returnval;
    uint8_t DirectionBit;
    struct gpiod_line_event Event;

    while(G2PanelActive)
    {
        returnval = gpiod_line_event_wait(VFO1, &ts);
        if(returnval > 0)
        {
            returnval = gpiod_line_event_read(VFO1, &Event);            // undocumented: this is needed to clear the event
            DirectionBit = gpiod_line_get_value(VFO2);
            if(DirectionBit)
              GDeltaCount--;
            else
              GDeltaCount++;
//            printf("delta count=%d\n", GDeltaCount);
        }
    }
}

int8_t EncoderStepTable[] =    {0,1,-1,2,
                                -1,0,2, 1,
                                1,2,0,-1,
                                2,-1,1,0};

//
// Encoder tick
// process its 2 new I/O inputs and update number of counts
//
void EncoderTick(uint32_t Enc, uint8_t Pin1, uint8_t Pin2)
{
    EncoderStates[Enc] = ((EncoderStates[Enc] << 2) | (Pin2 << 1) | Pin1) &0b1111;          // b0,1=new state; 2,3=prev state
    if(EncodersInitialised)
        EncoderCounts[Enc] += EncoderStepTable[EncoderStates[Enc]];
}


uint32_t TickCounter;
#define VFASTTICKSPERSLOWTICK 3


//
// read mechanical encoder
// step count needs to be halved because they advance 2 steps per click position
//
int8_t GetEncoderCount(uint8_t Enc)
{
    int8_t Result;

    Result = EncoderCounts[Enc]/2;
    EncoderCounts[Enc] = EncoderCounts[Enc]%2;
    return Result;
}


//
// periodic timestep
// perform a "fast tick" and then "slow tick" every N
//
void G2PanelTick(void *arg)
{
    int8_t Steps;
    uint8_t PinCntr;                            // interates IO pins
    uint32_t MCPData;
    uint32_t Cntr;

    while(G2PanelActive)
    {
        TickCounter++;
        gpiod_line_get_value_bulk(&PBInLines, IOPinValues);
//
// process encoders
//
        for(Cntr=0; Cntr < VNUMENCODERS; Cntr++)
            EncoderTick(Cntr, IOPinValues[2*Cntr], IOPinValues[2*Cntr+1]);
        EncodersInitialised = true;
//
//
//
        if(TickCounter >= VFASTTICKSPERSLOWTICK)
        {
            TickCounter=0;
    //
    // now read MCP I2C pushbuttons, and scan all pushbuttons
    //
            MCPData = i2c_read_word_data(0x12);                  // read GPIOA, B into bottom 16 bits
            for (Cntr = 16; Cntr < 20; Cntr++)
                MCPData |= (IOPinValues[Cntr] << Cntr);                     // add in PB IO pin

            for(PinCntr=0; PinCntr < VNUMBUTTONS; PinCntr++)
            {
                PBPinShifts[PinCntr] = ((PBPinShifts[PinCntr] << 1) | (MCPData & 1)) & 0b00000111;           // most recent 3 samples
                MCPData = MCPData >> 1;
                if(PBPinShifts[PinCntr] == 0b00000100)
                    printf("Pin %d pressed\n", PinCntr);
                else if (PBPinShifts[PinCntr] == 0b00000011)
                    printf("Pin %d released\n", PinCntr);
            }
            for(Cntr=0; Cntr < VNUMENCODERS; Cntr++)
            {
                Steps = GetEncoderCount(Cntr);
                if(Steps != 0)
                    printf("enc=%d  cnt=%d\n", Cntr, Steps);
            }
        }
        usleep(3333);                                                  // 3.3ms period
    }
}




//
// set all GPIO to required state
//
void SetupG2PanelGPIO(void)
{
    struct gpiod_line_request_config PBConfig;

    chip = NULL;

    //
    // Open GPIO device. Try devices for RPi4 and RPi5
    //
    if (chip == NULL)
    {
        gpio_device = "/dev/gpiochip4";      // works on RPI5
        chip = gpiod_chip_open(gpio_device);
    }

    if (chip == NULL)
    {
        gpio_device = "/dev/gpiochip0";     // works on RPI4
        chip = gpiod_chip_open(gpio_device);
    }

    //
    // If no connection, give up
    //
    if (chip == NULL)
        printf("%s: open chip failed\n", __FUNCTION__);
    else
    {
        printf("%s: G2 panel GPIO device=%s\n", __FUNCTION__, gpio_device);
        VFO1 = gpiod_chip_get_line(chip, 17);
        VFO2 = gpiod_chip_get_line(chip, 18);
        printf("assigning line inputs for VFO encoder\n");
        gpiod_line_request_rising_edge_events(VFO1, "VFO 1");
        gpiod_line_request_input(VFO2, "VFO 2");

        printf("assigning line inputs for pushbuttons & encoders\n");
        gpiod_chip_get_lines(chip, PBIOPins, VNUMGPIO, &PBInLines);
        gpiod_line_request_bulk(&PBInLines, &config, &IOPinValues);
    }
}




//
// set MCP23017 to required state
//
void SetupG2PanelI2C(void)
{
  int flags;

  // setup IOCONA, B
  if (i2c_write_byte_data(0x0A, 0x00) < 0) { return; }
  if (i2c_write_byte_data(0x0B, 0x00) < 0) { return; }

  // GPINTENA, B: disable interrupt
  if (i2c_write_byte_data(0x04, 0x00) < 0) { return; }
  if (i2c_write_byte_data(0x05, 0x00) < 0) { return; }

  // DEFVALA, B: clear defaults
  if (i2c_write_byte_data(0x06, 0x00) < 0) { return; }
  if (i2c_write_byte_data(0x07, 0x00) < 0) { return; }

  // OLATA, B: no output data
  if (i2c_write_byte_data(0x14, 0x00) < 0) { return; }
  if (i2c_write_byte_data(0x15, 0x00) < 0) { return; }

  // set GPIOA, B to have pullups
  if (i2c_write_byte_data(0x0C, 0xFF) < 0) { return; }
  if (i2c_write_byte_data(0x0D, 0xFF) < 0) { return; }

  // IOPOLA, B: non inverted polarity polarity
  if (i2c_write_byte_data(0x02, 0x00) < 0) { return; }
  if (i2c_write_byte_data(0x03, 0x00) < 0) { return; }

  // IODIRA, B: set GPIOA/B for input
  if (i2c_write_byte_data(0x00, 0xFF) < 0) { return; }
  if (i2c_write_byte_data(0x01, 0xFF) < 0) { return; }

  // INTCONA, B
  if (i2c_write_byte_data(0x08, 0x00) < 0) { return; }
  if (i2c_write_byte_data(0x09, 0x00) < 0) { return; }
}








//
// function to initialise a connection to the G2 front panel; call if selected as a command line option
//
void InitialiseG2PanelHandler(void)
{
    G2PanelControlled = true;
    SetupG2PanelGPIO();
    SetupG2PanelI2C();

    G2PanelActive = true;                                   // enable threads
    if(pthread_create(&VFOEncoderThread, NULL, VFOEventHandler, NULL) < 0)
        perror("pthread_create VFO encoder");
    pthread_detach(VFOEncoderThread);

    if(pthread_create(&G2PanelTickThread, NULL, G2PanelTick, NULL) < 0)
        perror("pthread_create G2 panel tick");
    pthread_detach(G2PanelTickThread);
}


//
// function to shutdown a connection to the G2 front panel; call if selected as a command line option
//
void ShutdownG2PanelHandler(void)
{
    if (chip != NULL)
    {
        G2PanelActive = false;
        sleep(2);                                       // wait 2s to allow threads to close
        gpiod_line_release(VFO1);
        gpiod_line_release(VFO2);
        gpiod_line_release_bulk(&PBInLines);
        gpiod_chip_close(chip);
    }
}




