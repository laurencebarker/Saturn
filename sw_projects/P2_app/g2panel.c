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

#include <linux/i2c-dev.h>
#include "../common/saturnregisters.h"
#include "../common/saturndrivers.h"
#include "../common/hwaccess.h"
#include "../common/debugaids.h"
#include "cathandler.h"
#include "i2cdriver.h"
#include "cathandler.h"
#include "andromedacatmessages.h"


//
// define is enabled if pane behaves as original andromeda
// for panel to behave as "stripped down" G2V2 (future) comment this out!
// (this is only needed until Thetis support is readily available)
//
//#define LEGACYANDROMEDA 1


//
// parameters for eZZZS version string
//
#define HWVERSION 2                         // andromeda V2


#ifdef LEGACYANDROMEDA
#define PRODUCTID 1                         // report as being an Andromeda panel
#else
#define PRODUCTID 4                         // report as being G2
#endif

int i2c_fd;                                  // file reference
char* pi_i2c_device = "/dev/i2c-1";
unsigned int G2MCP23017 = 0x20;                     // i2c slave address of MCP23017 on G2 panel
unsigned int G2V2Arduino = 0x15;                    // i2c slave address of Arduino on G2V2

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
bool CATDetected = false;                           // true if panel ID message has been sent
uint32_t VKeepAliveCount;                           // count of ticks for keepalive

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
// initialised to 0xFF as buttons expected to be released (1 input) at startup
//
uint8_t PBPinShifts [VNUMBUTTONS] =    {0xFF, 0xFF, 0xFF, 0xFF,
                                        0xFF, 0xFF, 0xFF, 0xFF, 
                                        0xFF, 0xFF, 0xFF, 0xFF, 
                                        0xFF, 0xFF, 0xFF, 0xFF,
                                        0xFF, 0xFF, 0xFF, 0xFF};

//
// long count tick counter for each button. If it reaches zero, a long press has occurred.
//
uint8_t PBLongCount [VNUMBUTTONS] =    {0x0, 0x0, 0x0, 0x0,
                                        0x0, 0x0, 0x0, 0x0, 
                                        0x0, 0x0, 0x0, 0x0, 
                                        0x0, 0x0, 0x0, 0x0,
                                        0x0, 0x0, 0x0, 0x0};

uint8_t EncoderStates[VNUMENCODERS];            // current and previous 2 bit state
int8_t EncoderCounts[VNUMENCODERS];             // number of steps since last read
#define VLONGPRESSCOUNT 100                     // 1s for long press
#define VKEEPALIVECOUNT 1500                    // 15s period between keepalive requests

//
// lookup table from h/w encoder numbers to Andromeda-like encoder numbers
// (to give similar control settings in Thetis)
//

//
// lookup table from h/w pushbutton numbers to Andromeda-like button numbers
// (to give similar control settings in Thetis)
//
#ifdef LEGACYANDROMEDA
uint8_t LookupEncoderCode [] = {11, 12, 1, 2, 5, 6, 9, 10};
uint8_t LookupButtonCode [] = {47, 50, 45, 44, 31, 32, 30, 34, 35, 33, 36, 37, 38, 21, 42, 43, 11, 1, 5, 9};
#else
uint8_t LookupEncoderCode [] = {11, 12, 1, 2, 5, 6, 9, 10};
uint8_t LookupButtonCode [] = {47, 50, 45, 44, 31, 32, 30, 34, 35, 33, 36, 37, 38, 21, 42, 43, 11, 1, 5, 9};
//uint8_t LookupEncoderCode [] = {5, 6, 3, 4, 9, 10, 7, 8};
//uint8_t LookupButtonCode [] = {7, 6, 8, 9, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 3, 2, 13, 12};
#endif



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



//
// function to check if panel is present. 
// file can be left open if "yes".
//
bool CheckG2PanelPresent(void)
{
    bool Result = false;
    uint16_t i2cdata;
    bool Error;


    i2c_fd=open(pi_i2c_device, O_RDWR);
    if(i2c_fd < 0)
        printf("failed to open i2c device\n");
    else if(ioctl(i2c_fd, I2C_SLAVE, G2MCP23017) >= 0)
        // check for G2 front panel on i2c. Change device address then byte read
    {
        i2cdata = i2c_read_byte_data(0x0, &Error);              // trial read
        if (!Error)
            Result = true;
        else
            close(i2c_fd);
    }
    return Result;    
}



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
    int8_t Steps;                               // encoder strp count
    uint8_t ScanCode;
    uint8_t PinCntr;                            // interates IO pins
    uint32_t MCPData;
    uint32_t Cntr;
    uint32_t Version;
    uint32_t CatParam;
    bool I2Cerror;

    while(G2PanelActive)
    {
        if(CATPortAssigned)                     // see if CAT has become available for the 1st time
        {
            if(CATDetected == false)
            {
                CATDetected = true;
                MakeProductVersionCAT(PRODUCTID, HWVERSION, GetP2appVersion());
            }
        }
        else
            CATDetected = false;
        TickCounter++;
        gpiod_line_get_value_bulk(&PBInLines, IOPinValues);
//
// process encoders
//
        for(Cntr=0; Cntr < VNUMENCODERS; Cntr++)
            EncoderTick(Cntr, IOPinValues[2*Cntr], IOPinValues[2*Cntr+1]);
        EncodersInitialised = true;
//
// execute slower code every 10ms
//
        if(TickCounter >= VFASTTICKSPERSLOWTICK)
        {
            TickCounter=0;
    //
    // now read MCP I2C pushbuttons, and scan all pushbuttons
    //
            MCPData = i2c_read_word_data(0x12, &I2Cerror);                  // read GPIOA, B into bottom 16 bits
            for (Cntr = 16; Cntr < 20; Cntr++)
                MCPData |= (IOPinValues[Cntr] << Cntr);                     // add in PB IO pin

            for(PinCntr=0; PinCntr < VNUMBUTTONS; PinCntr++)
            {
                PBPinShifts[PinCntr] = ((PBPinShifts[PinCntr] << 1) | (MCPData & 1)) & 0b00000111;           // most recent 3 samples
                MCPData = MCPData >> 1;
                ScanCode = LookupButtonCode[PinCntr];
                if(PBPinShifts[PinCntr] == 0b00000100)                      // button press detected
                {
                    MakePushbuttonCAT(ScanCode, 1);
                    PBLongCount[PinCntr] = VLONGPRESSCOUNT;                 // set long press count
                }
                else if (PBPinShifts[PinCntr] == 0b00000011)                // button release detected
                {
                    MakePushbuttonCAT(ScanCode, 0);
                    PBLongCount[PinCntr] = 0;                               // clear long press count
                }
                else if(PBLongCount[PinCntr] != 0)                          // if button pressed, and long press not yet declared
                {
                    if(--PBLongCount[PinCntr] == 0)
                    {
                        MakePushbuttonCAT(ScanCode, 2);
                    }
                }
            }
            //
            // read mechanical encoders
            //
            for(Cntr=0; Cntr < VNUMENCODERS; Cntr++)
            {
                ScanCode = LookupEncoderCode[Cntr];
                Steps = GetEncoderCount(Cntr);
                MakeEncoderCAT(Steps, ScanCode);
            }
            //
            // read optical encoder
            //
            Steps = ReadOpticalEncoder();
            MakeVFOEncoderCAT(Steps);
            //
            // check keepalive
            //
            if(VKeepAliveCount++ > VKEEPALIVECOUNT)
            {
                VKeepAliveCount = 0;
                MakeCATMessageNoParam(DESTTCPCATPORT, eZZXV);
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
    close(i2c_fd);
}




