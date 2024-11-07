/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 1 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// saturnregisters.c:
// Hardware access to FPGA registers in the Saturn FPGA
//  at the level of "set TX frequency" or set DDC frequency"
//
//////////////////////////////////////////////////////////////


#include "../common/saturnregisters.h"
#include "../common/hwaccess.h"                   // low level access
#include <stdlib.h>
#include <math.h>
#include <unistd.h>
#include "version.h"
#include <stdio.h>
#include <pthread.h>
#include <string.h>

//
// mutexes to protect registers that are accessed from several threads
//
pthread_mutex_t DDCInSelMutex = PTHREAD_MUTEX_INITIALIZER;
pthread_mutex_t RFGPIOMutex = PTHREAD_MUTEX_INITIALIZER;
pthread_mutex_t CodecRegMutex = PTHREAD_MUTEX_INITIALIZER;

// DefaultRegMutex is a less granular mutex, used for all mutations of registers
// not protected by the above register-specific mutexes
pthread_mutex_t DefaultRegMutex = PTHREAD_MUTEX_INITIALIZER;


//
// ROMs for DAC Current Setting and 0.5dB step digital attenuator
//
unsigned int DACCurrentROM[256];                    // used for residual attenuation
unsigned int DACStepAttenROM[256];                  // provides most atten setting


//
// local copies of values written to registers
//
#define VMAXP1DDCS 7                                // max number of DDCs used for P1
#define VSAMPLERATE 122880000                       // sample rate in Hz

uint32_t DDCDeltaPhase[VNUMDDC];                    // DDC frequency settings
uint32_t DUCDeltaPhase;                             // DUC frequency setting
uint32_t TestSourceDeltaPhase;                      // test source DDS delta phase
atomic_uint GStatusRegister;                        // most recent status register setting
uint32_t GPIORegValue;                              // value stored into GPIO
uint32_t TXConfigRegValue;                          // value written into TX config register
uint32_t DDCInSelReg;                               // value written into DDC config register
uint32_t DDCRateReg;                                // value written into DDC rate register
atomic_bool GADCOverride;                           // true if ADCs are to be overridden & use test source instead
atomic_bool GByteSwapEnabled;                       // true if byte swapping enabled for sample readout
atomic_bool GPTTEnabled;                            // true if PTT is enabled
atomic_bool MOXAsserted;                            // true if MOX as asserted
atomic_bool GPureSignalEnabled;                     // true if PureSignal is enabled
ESampleRate P1SampleRate;                           // rate for all DDC
atomic_uint P2SampleRates[VNUMDDC];                 // numerical sample rates for each DDC
atomic_uint GDDCEnabled;                            // 1 bit per DDC
atomic_bool GClassESetting;                         // NOT CURRENTLY USED - true if class E operation
atomic_bool GIsApollo;                              // NOT CURRENTLY USED - true if Apollo filter selected
atomic_bool GEnableApolloFilter;                    // Apollo filter bit - NOT USED
atomic_bool GEnableApolloATU;                       // Apollo ATU bit - NOT USED
atomic_bool GStartApolloAutoTune;                   // Start Apollo tune bit - NOT USED
atomic_bool GPPSEnabled;                            // NOT CURRENTLY USED - trie if PPS generation enabled
atomic_uint GTXDACCtrl;                             // TX DAC current setting & atten
atomic_uint GRXADCCtrl;                             // RX1 & 2 attenuations
atomic_bool GAlexRXOut;                             // P1 RX output bit (NOT USED)
atomic_uint GAlexTXFiltRegister;                    // 16 bit used of 32
atomic_uint GAlexTXAntRegister;                     // 16 bit used of 32
atomic_uint GAlexRXRegister;                        // 32 bit RX register
atomic_bool GRX2GroundDuringTX;                     // true if RX2 grounded while in TX
atomic_uint GAlexCoarseAttenuatorBits;              // Alex coarse atten NOT USED
atomic_bool GAlexManualFilterSelect;                // true if manual (remote CPU) filter setting
atomic_bool GEnableAlexTXRXRelay;                   // true if TX allowed
atomic_bool GCWKeysReversed;                        // true if keys reversed. Not yet used but will be
atomic_uint GCWKeyerSpeed;                          // Keyer speed in WPM. Not yet used
atomic_uint GCWKeyerMode;                           // Keyer Mode. True if mode B. Not yet used
atomic_uint GCWKeyerWeight;                         // Keyer Weight. Not yet used
atomic_bool GCWKeyerSpacing;                        // Keyer spacing
atomic_bool GCWIambicKeyerEnabled;                  // true if iambic keyer is enabled
atomic_uint GIambicConfigReg;                       // copy of iambic comfig register
atomic_uint GCWKeyerSetup;                          // keyer control register
atomic_uint GClassEPWMMin;                          // min class E PWM. NOT USED at present.
atomic_uint GClassEPWMMax;                          // max class E PWM. NOT USED at present.
atomic_uint GCodecConfigReg;                        // codec configuration
atomic_bool GSidetoneEnabled;                       // true if sidetone is enabled
atomic_uint GSidetoneVolume;                        // assigned sidetone volume (8 bit signed)
atomic_bool GWidebandADC1;                          // true if wideband on ADC1. For P2 - not used yet.
atomic_bool GWidebandADC2;                          // true if wideband on ADC2. For P2 - not used yet.
atomic_uint GWidebandSampleCount;                   // P2 - not used yet
atomic_uint GWidebandSamplesPerPacket;              // P2 - not used yet
atomic_uint GWidebandUpdateRate;                    // update rate in ms. P2 - not used yet.
atomic_uint GWidebandPacketsPerFrame;               // P2 - not used yet
atomic_uint GAlexEnabledBits;                       // P2. True if Alex1-8 enabled. NOT USED YET.
atomic_bool GPAEnabled;                             // P2. True if PA enabled. NOT USED YET.
atomic_uint GTXDACCount;                            // P2. #TX DACs. NOT USED YET.
ESampleRate GDUCSampleRate;                         // P2. TX sample rate. NOT USED YET.
atomic_uint GDUCSampleSize;                         // P2. DUC # sample bits. NOT USED YET
atomic_uint GDUCPhaseShift;                         // P2. DUC phase shift. NOT USED YET.
atomic_bool GSpeakerMuted;                          // P2. True if speaker muted.
atomic_bool GCWXMode;                               // True if in computer generated CWX mode
atomic_bool GCWXDot;                                // True if computer generated CW Dot.
atomic_bool GCWXDash;                               // True if computer generated CW Dash.
atomic_bool GDashPressed;                           // P2. True if dash input pressed.
atomic_bool GDotPressed;                            // P2. true if dot input pressed.
atomic_bool GCWEnabled;                             // true if CW mode
atomic_bool GBreakinEnabled;                        // true if break-in is enabled
atomic_uint GUserOutputBits;                        // P2. Not yet implermented.
atomic_uint GTXAmplScaleFactor;                     // values multipled into TX output after DUC
atomic_bool GTXAlwaysEnabled;                       // true if TX samples always enabled (for test)
atomic_bool GTXIQInterleaved;                       // true if IQ is interleaved, for EER mode
atomic_bool GTXDUCMuxActive;                        // true if I/Q mux is enabled to transfer data
atomic_bool GEEREnabled;                            // P2. true if EER is enabled
ETXModulationSource GTXModulationSource;            // values added to register
atomic_bool GTXProtocolP2;                          // true if P2
uint32_t TXModulationTestReg;                       // modulation test DDS
atomic_bool GEnableTimeStamping;                    // true if timestamps to be added to data. NOT IMPLEMENTED YET
atomic_bool GEnableVITA49;                          // true if to enable VITA49 formatting. NOT SUPPORTED YET
atomic_uint GCWKeyerRampms = 0;                     // ramp length for keyer, in ms
atomic_bool GCWKeyerRamp_IsP2 = false;              // true if ramp initialised for protocol 2

unsigned int DACCurrentROM[256];                    // used for residual attenuation
unsigned int DACStepAttenROM[256];                  // provides most atten setting
atomic_uint GNumADCs;                               // count of ADCs available


//
// local copies of Codec registers
//
atomic_uint GCodecLineGain;                        // value written in Codec left line in gain register
atomic_uint GCodecAnaloguePath;                    // value written in Codec analogue path register


//
// mic, bias & PTT bits in GPIO register:
//
#define VMICBIASENABLEBIT 0                         // GPIO bit definition
#define VMICPTTSELECTBIT 1                          // GPIO bit definition
#define VMICSIGNALSELECTBIT 2                       // GPIO bit definition
#define VMICBIASSELECTBIT 3                         // GPIO bit definition
#define VDATAENDIAN 26                              // GPIO bit definition


//
// define Codec registers
//
#define VCODECLLINEVOLREG 0                         // left line input volume
#define VCODECRLINEVOLREG 1                         // right line input volume
#define VCODECLHEADPHONEVOLREG 2                    // left headphone volume
#define VCODECRHEADPHONEVOLREG 3                    // right headphone volume
#define VCODECANALOGUEPATHREG 4                     // analogue path control
#define VCODECDIGITALPATHREG 5                      // digital path control
#define VCODECPOWERDOWNREG 6                        // power down control
#define VCODECDIGITALFORMATREG 7                    // digital audio interface format register
#define VCODECSAMPLERATEREG 8                       // sample rate control
#define VCODECACTIVATIONREG 9                       // digital interface activation register
#define VCODECRESETREG 15                           // reset register

//
// DMA FIFO depths - the number of 64 bit FIFO locations
// Version-dependent & set by InitialiseFIFOSizes()
//
uint32_t DMAFIFODepths[VNUMDMAFIFO] = {0};


//
// addresses of the DDC frequency registers
//
uint32_t DDCRegisters[VNUMDDC] =
{
  VADDRDDC0REG,
  VADDRDDC1REG,
  VADDRDDC2REG,
  VADDRDDC3REG,
  VADDRDDC4REG,
  VADDRDDC5REG,
  VADDRDDC6REG,
  VADDRDDC7REG,
  VADDRDDC8REG,
  VADDRDDC9REG
};


//
// ALEX SPI registers
//
#define VOFFSETALEXTXFILTREG 0                          // offset addr in IP core: TX filt, RX ant
#define VOFFSETALEXRXREG 4                              // offset addr in IP core
#define VOFFSETALEXTXANTREG 8                           // offset addr in IP core: TX filt, TX ant


//
// bit addresses in status and GPIO registers
//
#define VMICBIASENABLEBIT 0
#define VMICPTTSELECTBIT 1
#define VMICSIGNALSELECTBIT 2
#define VMICBIASSELECTBIT 3
#define VSPKRMUTEBIT 4
#define VBALANCEDMICSELECT 5
#define VADC1RANDBIT 8
#define VADC1PGABIT 9
#define VADC1DITHERBIT 10
#define VADC2RANDBIT 11
#define VADC2PGABIT 12
#define VADC2DITHERBIT 13
#define VOPENCOLLECTORBITS 16           // bits 16-22
#define VMOXBIT 24
#define VTXENABLEBIT 25
#define VTXRELAYDISABLEBIT 27
#define VPURESIGNALENABLE 28            // not used by this hardware
#define VATUTUNEBIT 29
#define VXVTRENABLEBIT 30

#define VPTTIN1BIT 0
#define VPTTIN2BIT 1                    // not currently used
#define VKEYINA 2                       // dot key
#define VKEYINB 3                       // dash key
#define VUSERIO4 4
#define VUSERIO5 5
#define VUSERIO6 6
#define VUSERIO8 7
#define V13_8VDETECTBIT 8
#define VATUTUNECOMPLETEBIT 9
#define VPLLLOCKED 10
#define VCWKEYDOWN 11                   // keyer output 
#define VEXTTXENABLEBIT 31


//
// Keyer setup register defines
//
#define VCWKEYERENABLE 31                               // enable bit
#define VCWKEYERDELAY 0                                 // delay bits 7:0
#define VCWKEYERHANG 8                                  // hang time is 17:8
#define VCWKEYERRAMP 18                                 // ramp time
#define VRAMPSIZE 4096                                  // max ramp length in words


//
// Iambic config register defines
//
#define VIAMBICSPEED 0                                  // speed bits 7:0
#define VIAMBICWEIGHT 8                                 // weight bits 15:8
#define VIAMBICREVERSED 16                              // keys reversed bit 16
#define VIAMBICENABLE 17                                // keyer enabled bit 17
#define VIAMBICMODE 18                                  // mode bit 18
#define VIAMBICSTRICT 19                                // strict spacing bit 19
#define VIAMBICCWX 20                                   // CWX enable bit 20
#define VIAMBICCWXDOT 21                                // CWX dox bit 21
#define VIAMBICCWXDASH 22                               // CWX dash bit 22
#define VCWBREAKIN 23                                   // breakin bit (CW not Iambic strictly!)
#define VIAMBICCWXBITS 0x00700000                       // all CWX bits
#define VIAMBICBITS 0x000FFFFF                          // all non CWX bits


//
// TX config register defines
//

#define VTXCONFIGDATASOURCEBIT 0
#define VTXCONFIGSAMPLEGATINGBIT 2
#define VTXCONFIGPROTOCOLBIT 3
#define VTXCONFIGSCALEBIT 4
#define VTXCONFIGMUXRESETBIT 29
#define VTXCONFIGIQDEINTERLEAVEBIT 30
#define VTXCONFIGIQSTREAMENABLED 31


// Helper functions for safe reading & writing
inline uint32_t get_uint32(const uint8_t *buffer, size_t offset) {
  uint32_t value;
  memcpy(&value, buffer + offset, sizeof(uint32_t));
  return ntohl(value);
}

inline uint16_t get_uint16(const uint8_t *buffer, size_t offset) {
  uint16_t value;
  memcpy(&value, buffer + offset, sizeof(uint16_t));
  return ntohs(value);
}

inline uint8_t get_uint8(const uint8_t *buffer, size_t offset) {
  uint8_t value;
  memcpy(&value, buffer + offset, sizeof(uint8_t));
  return value;
}

inline void put_uint32(uint8_t *buffer, size_t offset, uint32_t value) {
  value = htonl(value);
  memcpy(buffer + offset, &value, sizeof(uint32_t));
}

inline void put_uint16(uint8_t *buffer, size_t offset, uint16_t value) {
  value = htons(value);
  memcpy(buffer + offset, &value, sizeof(uint16_t));
}

inline void put_uint8(uint8_t *buffer, size_t offset, uint8_t value) {
  buffer[offset] = value;
}


//
// InitialiseFIFOSizes(void)
// Initialise the FIFO size table, which is FPGA version dependent.
//
// Should be called in the main thread before other threads are created.
void InitialiseFIFOSizes(void)
{
  FirmwareInfo fwInfo = GetFirmwareInfo();
  unsigned int Version = fwInfo.version;

  if((Version >= 10) && (Version <= 12))
  {
    printf("loading new FIFO sizes for updated firmware <= 12\n");
    DMAFIFODepths[0] = 16384;  //  eRXDDCDMA,     selects RX
    DMAFIFODepths[1] = 2048;   //  eTXDUCDMA,     selects TX
    DMAFIFODepths[2] = 256;    //  eMicCodecDMA,  selects mic samples
    DMAFIFODepths[3] = 1024;   //  eSpkCodecDMA   selects speaker samples
  }
  else if(Version >= 13)
  {
    printf("loading new FIFO sizes for updated firmware V13+\n");
    DMAFIFODepths[0] = 16384;  //  eRXDDCDMA,     selects RX
    DMAFIFODepths[1] = 4096;   //  eTXDUCDMA,     selects TX
    DMAFIFODepths[2] = 256;    //  eMicCodecDMA,  selects mic samples
    DMAFIFODepths[3] = 1024;   //  eSpkCodecDMA   selects speaker samples
  }

  // Memory barrier to ensure visibility to other threads
  atomic_thread_fence(memory_order_release);
}


static uint32_t ReadProductInformationRegister(void)
{
  pthread_mutex_lock(&DefaultRegMutex);
  uint32_t productInformation = RegisterRead(VADDRPRODVERSIONREG);
  pthread_mutex_unlock(&DefaultRegMutex);
  return productInformation;
}

static uint32_t ReadDateCodeRegister(void)
{
  pthread_mutex_lock(&DefaultRegMutex);
  uint32_t dateCode = RegisterRead(VADDRUSERVERSIONREG);
  pthread_mutex_unlock(&DefaultRegMutex);
  return dateCode;
}

ProductInfo GetProductInfo(void)
{
  uint32_t productInformation = ReadProductInformationRegister();

  ProductInfo info;
  info.productVersion = productInformation & 0xFFFF;
  info.productId = productInformation >> 16;

  return info;
}

uint32_t GetDateCode(void)
{
  return ReadDateCodeRegister();
}

FullVersionInfo GetFullVersionInfo(void)
{
  FullVersionInfo info;
  info.firmware = GetFirmwareInfo();
  info.product = GetProductInfo();
  info.dateCode = GetDateCode();
  return info;
}



//
// initialise the DAC Atten ROMs
// these set the step attenuator and DAC drive level
// for "attenuation intent" values from 0 to 255
//
void InitialiseDACAttenROMs(void)
{
    unsigned int Level;                         // input demand value
    double DesiredAtten;                        // desired attenuation in dB
    unsigned int StepValue;                     // integer step atten drive value
    double ResidualAtten;                       // atten to go in the current setting DAC
    unsigned int DACDrive;                      // int value to go to DAC ROM

//
// do the max atten values separately; then calculate point by point
//
    DACCurrentROM[0] = 0;                       // min level
    DACStepAttenROM[0] = 63;                    // max atten

    for (Level = 1; Level < 256; Level++)
    {
        DesiredAtten = 20.0*log10(255.0/(double)Level);     // this is the atten value we want after the high speed DAC
        StepValue = (int)(2.0*DesiredAtten);                // 6 bit step atten should be set to
        if(StepValue > 63)                                  // clip to 6 bits
            StepValue = 63;
        ResidualAtten = DesiredAtten - ((double)StepValue * 0.5);        // this needs to be achieved through the current setting drive
        DACDrive = (unsigned int)(255.0/pow(10.0,(ResidualAtten/20.0)));
        DACCurrentROM[Level] = DACDrive;
        DACStepAttenROM[Level] = StepValue;
    }
}


//
// SetByteSwapping(bool)
// set whether byte swapping is enabled. True if yes, to get data in network byte order.
//
void SetByteSwapping(bool IsSwapped)
{
    uint32_t Register;

    pthread_mutex_lock(&RFGPIOMutex);               // get protected access
    Register = GPIORegValue;                        // get current settings
    GByteSwapEnabled = IsSwapped;
    if(IsSwapped)
        Register |= (1<<VDATAENDIAN);               // set bit for swapped to network order
    else
        Register &= ~(1<<VDATAENDIAN);              // clear bit for raspberry pi local order

    GPIORegValue = Register;                        // store it back
    RegisterWrite(VADDRRFGPIOREG, Register);        // and write to it
    pthread_mutex_unlock(&RFGPIOMutex);             // clear protection
}


//
// internal function to set the keyer on or off
// needed because keyer setting can change by message, of by TX operation
//
void ActivateCWKeyer(bool Keyer)
{
    uint32_t Register;
    pthread_mutex_lock(&DefaultRegMutex);
    Register = GCWKeyerSetup;                           // get current settings
    if(Keyer)
        Register |= (UINT32_C(1) << VCWKEYERENABLE);
    else
        Register &= ~(UINT32_C(1) << VCWKEYERENABLE);
    if(Register != GCWKeyerSetup)                       // write back if different
    {
        GCWKeyerSetup = Register;                       // store it back
        RegisterWrite(VADDRKEYERCONFIGREG, Register);   // and write to it
    }
    pthread_mutex_unlock(&DefaultRegMutex);
}


//
// SetMOX(bool Mox)
// sets or clears TX state
// set or clear the relevant bit in GPIO
// and enable keyer if CW
//
void SetMOX(bool Mox) {
  uint32_t Register;

  pthread_mutex_lock(&RFGPIOMutex);               // get protected access
  Register = GPIORegValue;                        // get current settings
  MOXAsserted = Mox;                              // set variable
  if (Mox)
    Register |= (UINT32_C(1) << VMOXBIT);
  else
    Register &= ~(UINT32_C(1) << VMOXBIT);
  GPIORegValue = Register;                        // store it back
  RegisterWrite(VADDRRFGPIOREG, Register); // and write to it
  //
  // now set CW keyer if required
  //
  if (Mox) {
    ActivateCWKeyer(GCWEnabled);
  } else {
    ActivateCWKeyer(GCWEnabled && GBreakinEnabled); // disable keyer unless CW & breakin
  }

  pthread_mutex_unlock(&RFGPIOMutex);
}


//
// SetTXEnable(bool Enabled)
// sets or clears TX enable bit
// set or clear the relevant bit in GPIO
//
void SetTXEnable(bool Enabled)
{
    uint32_t Register;

    pthread_mutex_lock(&RFGPIOMutex);               // get protected access
    Register = GPIORegValue;                        // get current settings
    if (Enabled)
        Register |= (UINT32_C(1) << VTXENABLEBIT);
    else
        Register &= ~(UINT32_C(1) << VTXENABLEBIT);
    GPIORegValue = Register;                        // store it back
    RegisterWrite(VADDRRFGPIOREG, Register);        // and write to it
    pthread_mutex_unlock(&RFGPIOMutex);             // clear protected access
}


//
// SetATUTune(bool TuneEnabled)
// drives the ATU tune output to selected state.
// set or clear the relevant bit in GPIO
//
void SetATUTune(bool TuneEnabled)
{
    uint32_t Register;
    pthread_mutex_lock(&RFGPIOMutex);               // get protected access
    Register = GPIORegValue;                        // get current settings
    if (TuneEnabled)
        Register |= (UINT32_C(1) << VATUTUNEBIT);
    else
        Register &= ~(UINT32_C(1) << VATUTUNEBIT);
    GPIORegValue = Register;                        // store it back
    RegisterWrite(VADDRRFGPIOREG, Register);        // and write to it
    pthread_mutex_unlock(&RFGPIOMutex);             // clear protected access
}


//
// SetP1SampleRate(ESampleRate Rate, unsigned int Count)
// sets the sample rate for all DDC used in protocol 1. 
// allowed rates are 48KHz to 384KHz.
// also sets the number of enabled DDCs, 1-8. Count = #DDC reqd
// DDCs are enabled by setting a rate; if rate bits=000, DDC is not enabled
// and for P1, no DDCs are interleaved
//
void SetP1SampleRate(ESampleRate Rate, unsigned int DDCCount)
{
    unsigned int Cntr;
    uint32_t RegisterValue = 0;
    uint32_t RateBits;

    if (DDCCount > VMAXP1DDCS)                             // limit the number of DDC to max allowed
        DDCCount = VMAXP1DDCS;
    RateBits = (uint32_t)Rate;                          // bits to go in DDC word
    P1SampleRate = Rate;                                // rate for all DDC
//
    // set all DDC up to max to rate; rest to 0
    for (Cntr = 0; Cntr < (DDCCount + 1); Cntr++)
    {
        RegisterValue |= RateBits;                      // add in rate bits for this DDC
        RateBits = RateBits << 3;                       // get ready for next DDC
    }
    if (RegisterValue != DDCRateReg)                     // write back if changed
    {
        DDCRateReg = RegisterValue;                     // write back
//        RegisterWrite(VADDRDDCRATES, RegisterValue);        // and write to h/w register
    }
}


//
// SetP2SampleRate(unsigned int DDC, bool Enabled, unsigned int SampleRate, bool InterleaveWithNext)
// sets the sample rate for a single DDC (used in protocol 2)
// allowed rates are 48KHz to 1536KHz.
// This sets the DDCRateReg variable and does NOT write to hardware
// The WriteP2DDCRateRegister() call must be made after setting values for all DDCs
//
void SetP2SampleRate(unsigned int DDC, bool Enabled, unsigned int SampleRate, bool InterleaveWithNext)
{
    uint32_t RegisterValue;
    uint32_t Mask;
    ESampleRate Rate;
  pthread_mutex_lock(&DefaultRegMutex);

    Mask = 7 << (DDC * 3);                      // 3 bits in correct position
    if (!Enabled)                                   // if not enabled, clear sample rate value & enabled flag
    {
        P2SampleRates[DDC] = 0;
        GDDCEnabled &= ~(UINT32_C(1) << DDC);                 // clear enable bit
        Rate = eDisabled;

    }
    else
    {
        P2SampleRates[DDC] = SampleRate;
        GDDCEnabled |= (UINT32_C(1) << DDC);                  // set enable bit
        if (InterleaveWithNext)
            Rate = eInterleaveWithNext;
        else
        {
            // look up enum value
            Rate = e48KHz;                          // assume 48KHz; then check other rates
            if (SampleRate == 96)
                Rate = e96KHz;
            else if (SampleRate == 192)
                Rate = e192KHz;
            else if (SampleRate == 384)
                Rate = e384KHz;
            else if (SampleRate == 768)
                Rate = e768KHz;
            else if (SampleRate == 1536)
                Rate = e1536KHz;
        }
    }

    RegisterValue = DDCRateReg;                     // get current register setting
    RegisterValue &= ~Mask;                         // strip current bits
    Mask = (uint32_t)Rate;                          // new bits
    Mask = Mask << (DDC * 3);                       // get new bits to right bit position
    RegisterValue |= Mask;
    DDCRateReg = RegisterValue;                     // don't save to hardware
  pthread_mutex_unlock(&DefaultRegMutex);
}


//
// bool WriteP2DDCRateRegister(void)
// writes the DDCRateRegister, once all settings have been made
// this is done so the number of changes to the DDC rates are minimised
// and the information all comes form one P2 message anyway.
// returns true if changes were made to the hardware register
//
bool WriteP2DDCRateRegister(void)
{
    pthread_mutex_lock(&DefaultRegMutex);
    uint32_t CurrentValue;                          // current register setting
    bool Result = false;                            // return value
    CurrentValue = RegisterRead(VADDRDDCRATES);
    if (CurrentValue != DDCRateReg)
        Result = true;
    RegisterWrite(VADDRDDCRATES, DDCRateReg);        // and write to hardware register
    pthread_mutex_unlock(&DefaultRegMutex);
    return Result;
}



//
// uint32_t GetDDCEnables(void)
// get enable bits for each DDC; 1 bit per DDC
// this is needed to set timings and sizes for DMA transfers
//
uint32_t GetDDCEnables(void)
{
    return GDDCEnabled;
}


//
// SetClassEPA(bool IsClassE)
// enables non-linear PA mode
// This is not usded in the current Saturn design
//
void SetClassEPA(bool IsClassE)
{
    GClassESetting = IsClassE;
}


//
// SetOpenCollectorOutputs(unsigned int bits)
// sets the 7 open collector output bits
//
void SetOpenCollectorOutputs(unsigned int bits)
{
    uint32_t Register;                              // FPGA register content
    uint32_t BitMask;                               // bitmask for 7 OC bits

    pthread_mutex_lock(&RFGPIOMutex);               // get protected access
    Register = GPIORegValue;                        // get current settings
    BitMask = (0b1111111) << VOPENCOLLECTORBITS;
    Register = Register & ~BitMask;                 // strip old bits, add new
    Register |= (bits << VOPENCOLLECTORBITS);
    GPIORegValue = Register;                        // store it back
    RegisterWrite(VADDRRFGPIOREG, Register);  // and write to it
    pthread_mutex_unlock(&RFGPIOMutex);             // clear protected access
}


//
// SetADCCount(unsigned int ADCCount)
// sets the number of ADCs available in the hardware.
//
void SetADCCount(unsigned int ADCCount)
{
    GNumADCs = ADCCount;                            // just save the value
}



//
// SetADCOptions(EADCSelect ADC, bool Dither, bool Random);
// sets the ADC contol bits for one ADC
//
void SetADCOptions(EADCSelect ADC, bool PGA, bool Dither, bool Random)
{
    uint32_t Register;                              // FPGA register content
    uint32_t RandBit = VADC1RANDBIT;                // bit number for Rand
    uint32_t PGABit = VADC1PGABIT;                  // bit number for Dither
    uint32_t DitherBit = VADC1DITHERBIT;            // bit number for Dither

    if(ADC != eADC1)                                // for ADC2, these are all 3 bits higher
    {
        RandBit += 3;
        PGABit += 3;
        DitherBit += 3;
    }
    pthread_mutex_lock(&RFGPIOMutex);               // get protected access
    Register = GPIORegValue;                        // get current settings
    Register &= ~(UINT32_C(1) << RandBit);                    // strip old bits
    Register &= ~(UINT32_C(1) << PGABit);
    Register &= ~(UINT32_C(1) << DitherBit);

    if(PGA)                                         // add new bits where set
        Register |= (UINT32_C(1) << PGABit);
    if(Dither)
        Register |= (UINT32_C(1) << DitherBit);
    if(Random)
        Register |= (UINT32_C(1) << RandBit);

    GPIORegValue = Register;                    // store it back
    RegisterWrite(VADDRRFGPIOREG, Register);  // and write to it
    pthread_mutex_unlock(&RFGPIOMutex);         // clear protected access
}

#define VTWOEXP32 4294967296.0              // 2^32

//
// SetDDCFrequency(uint32_t DDC, uint32_t Value, bool IsDeltaPhase)
// sets a DDC frequency.
// DDC: DDC number (0-9)
// Value: 32 bit phase word or frequency word (1Hz resolution)
// IsDeltaPhase: true if a delta phase value, false if a frequency value (P1)
// calculate delta phase if required. Delta=2^32 * (F/Fs)
// store delta phase; write to FPGA register.
//
void SetDDCFrequency(uint32_t DDC, uint32_t Value, bool IsDeltaPhase)
{
    uint32_t DeltaPhase;                    // calculated deltaphase value
    uint32_t RegAddress;
    double fDeltaPhase;
    pthread_mutex_lock(&DefaultRegMutex);
    if(DDC >= VNUMDDC)                      // limit the DDC count to actual regs!
        DDC = VNUMDDC-1;
    if(!IsDeltaPhase)                       // ieif protocol 1
    {
        fDeltaPhase = VTWOEXP32 * (double)Value / (double) VSAMPLERATE;
        DeltaPhase = (uint32_t)fDeltaPhase;
    }
    else
        DeltaPhase = (uint32_t)Value;

    if(DDCDeltaPhase[DDC] != DeltaPhase)    // write back if changed
    {
        DDCDeltaPhase[DDC] = DeltaPhase;        // store this delta phase
        RegAddress =DDCRegisters[DDC];          // get DDC reg address, 
        RegisterWrite(RegAddress, DeltaPhase);  // and write to it
    }
    pthread_mutex_unlock(&DefaultRegMutex);
}


//
// SetTestDDSFrequency(uint32_t Value, bool IsDeltaPhase)
// sets a test source frequency.
// Value: 32 bit phase word or frequency word (1Hz resolution)
// IsDeltaPhase: true if a delta phase value, false if a frequency value (P1 or local app)
// calculate delta phase if required. Delta=2^32 * (F/Fs)
// store delta phase; write to FPGA register.
//
void SetTestDDSFrequency(uint32_t Value, bool IsDeltaPhase)
{
    uint32_t DeltaPhase;                    // calculated deltaphase value
    double fDeltaPhase;

  pthread_mutex_lock(&DefaultRegMutex);
    if(!IsDeltaPhase)                       // ie if protocol 1
    {
        fDeltaPhase = VTWOEXP32 * (double)Value / (double) VSAMPLERATE;
        DeltaPhase = (uint32_t)fDeltaPhase;
    }
    else
        DeltaPhase = (uint32_t)Value;

    if(TestSourceDeltaPhase != DeltaPhase)    // write back if changed
    {
        TestSourceDeltaPhase = DeltaPhase;        // store this delta phase
        RegisterWrite(VADDRRXTESTDDSREG, DeltaPhase);  // and write to it
    }
  pthread_mutex_unlock(&DefaultRegMutex);
}


//
// SetDUCFrequency(unsigned int Value, bool IsDeltaPhase)
// sets a DUC frequency. (Currently only 1 DUC, therefore DUC must be 0)
// Value: 32 bit phase word or frequency word (1Hz resolution)
// IsDeltaPhase: true if a delta phase value, false if a frequency value (P1)
//
void SetDUCFrequency(unsigned int Value, bool IsDeltaPhase)		// only accepts DUC=0 
{
    uint32_t DeltaPhase;                    // calculated deltaphase value
    double fDeltaPhase;

    pthread_mutex_lock(&DefaultRegMutex);
    if(!IsDeltaPhase)                       // ieif protocol 1
    {
        fDeltaPhase = VTWOEXP32 * (double)Value / (double) VSAMPLERATE;
        DeltaPhase = (uint32_t)fDeltaPhase;
    }
    else
        DeltaPhase = (uint32_t)Value;

    DUCDeltaPhase = DeltaPhase;             // store this delta phase
    RegisterWrite(VADDRTXDUCREG, DeltaPhase);  // and write to it
  pthread_mutex_unlock(&DefaultRegMutex);
}




//
//////////////////////////////////////////////////////////////////////////////////
//	data to send to Alex Tx filters is in the following format:
//	Bit  0 - NC				U3 - D0     0
//	Bit  1 - NC				U3 - D1     0
//	Bit  2 - txrx_status    U3 - D2     TXRX_Relay strobe
//	Bit  3 - Yellow Led		U3 - D3     RX2_GROUND: from C0=0x24: C1[7]
//	Bit  4 - 30/20m	LPF		U3 - D4     LPF[0] : from C0=0x12: C4[0]
//	Bit  5 - 60/40m	LPF		U3 - D5     LPF[1] : from C0=0x12: C4[1]
//	Bit  6 - 80m LPF		U3 - D6     LPF[2] : from C0=0x12: C4[2]
//	Bit  7 - 160m LPF    	U3 - D7     LPF[3] : from C0=0x12: C4[3]
//	Bit  8 - Ant #1			U5 - D0     Gate from C0=0:C4[1:0]=00
//	Bit  9 - Ant #2			U5 - D1     Gate from C0=0:C4[1:0]=01
//	Bit 10 - Ant #3			U5 - D2     Gate from C0=0:C4[1:0]=10
//	Bit 11 - T/R relay		U5 - D3     T/R relay. 1=TX	TXRX_Relay strobe
//	Bit 12 - Red Led		U5 - D4     TXRX_Relay strobe
//	Bit 13 - 6m	LPF			U5 - D5     LPF[4] : from C0=0x12: C4[4]
//	Bit 14 - 12/10m LPF		U5 - D6     LPF[5] : from C0=0x12: C4[5]
//	Bit 15 - 17/15m	LPF		U5 - D7     LPF[6] : from C0=0x12: C4[6]
// bit 4 (or bit 11 as sent by AXI) replaced by TX strobe

//	data to send to Alex Rx filters is in the folowing format:
//  bits 15:0 - RX1; bits 31:16 - RX1
// (IC designators and functions for 7000DLE RF board)
//	Bit  0 - Yellow LED 	  U6 - QA       0
//	Bit  1 - 10-22 MHz BPF 	  U6 - QB       BPF[0]: from C0=0x12: C3[0]
//	Bit  2 - 22-35 MHz BPF 	  U6 - QC       BPF[1]: from C0=0x12: C3[1]
//	Bit  3 - 6M Preamp    	  U6 - QD       10/6M LNA: from C0=0x12: C3[6]
//	Bit  4 - 6-10MHz BPF	  U6 - QE       BPF[2]: from C0=0x12: C3[2]
//	Bit  5 - 2.5-6 MHz BPF 	  U6 - QF       BPF[3]: from C0=0x12: C3[3]
//	Bit  6 - 1-2.5 MHz BPF 	  U6 - QG       BPF[4]: from C0=0x12: C3[4]
//	Bit  7 - N/A      		  U6 - QH       0
//	Bit  8 - Transverter 	  U10 - QA      Gated C122_Transverter. True if C0=0: C3[6:5]=11
//	Bit  9 - Ext1 In      	  U10 - QB      Gated C122_Rx_2_in. True if C0=0: C3[6:5]=10
//	Bit 10 - N/A         	  U10 - QC      0
//	Bit 11 - PS sample select U10 - QD      Selects main or RX_BYPASS_OUT	Gated C122_Rx_1_in True if C0=0: C3[6:5]=01
//	Bit 12 - RX1 Filt bypass  U10 - QE      BPF[5]: from C0=0x12: C3[5]
//	Bit 13 - N/A 		      U10 - QF      0
//	Bit 14 - RX1 master in	  U10 - QG      (selects main, or transverter/ext1)	Gated. True if C0=0: C3[6:5]=11 or C0=0: C3[6:5]=10 
//	Bit 15 - RED LED 	      U10 - QH      0
//	Bit 16 - Yellow LED 	  U7 - QA       0
//	Bit 17 - 10-22 MHz BPF 	  U7 - QB       BPF2[0]: from C0=0x24: C1[0]
//	Bit 18 - 22-35 MHz BPF 	  U7 - QC       BPF2[1]: from C0=0x24: C1[1]
//	Bit 19 - 6M Preamp    	  U7 - QD       10/6M LNA2: from C0=0x24: C1[6]
//	Bit 20 - 6-10MHz BPF	  U7 - QE       BPF2[2]: from C0=0x24: C1[2]
//	Bit 21 - 2.5-6 MHz BPF 	  U7 - QF       BPF2[3]: from C0=0x24: C1[3]
//	Bit 22 - 1-2.5 MHz BPF 	  U7 - QG       BPF2[4]: from C0=0x24: C1[4]
//	Bit 23 - N/A      		  U7 - QH       0
//	Bit 24 - RX2_GROUND 	  U13 - QA      RX2_GROUND: from C0=0x24: C1[7]
//	Bit 25 - N/A         	  U13 - QB      0
//	Bit 26 - N/A         	  U13 - QC      0
//	Bit 27 - N/A              U13 - QD      0
//	Bit 28 - HPF_BYPASS 2	  U13 - QE      BPF2[5]: from C0=0x24: C1[5]
//	Bit 29 - N/A 		      U13 - QF      0
//	Bit 30 - N/A	          U13 - QG      0
//	Bit 31 - RED LED 2	      U13 - QH      0



//
// SetAlexRXAnt(unsigned int Bits)
// P1: set the Alex RX antenna bits.
// bits=00: none; 01: RX1; 02: RX2; 03: transverter
// affects bits 8,9,11,14 of the Alex RX register
//
void SetAlexRXAnt(unsigned int Bits)
{
    uint32_t Register;                                  // modified register
    pthread_mutex_lock(&DefaultRegMutex);
    Register = GAlexRXRegister;                         // copy original register
    Register &= 0xFFFFB4FF;                             // turn off all affected bits

    switch(Bits)
    {
        case 0:
        default:
            break;
        case 1:
            Register |= 0x00000800;                       // turn on PS select bit
            break;

        case 2:
            Register |= 00004200;                       // turn on master in & EXT1 bits
            break;
        case 3:
            Register |= 00004100;                       // turn on master in & transverter bits
            break;
    }
    if(Register != GAlexRXRegister)                     // write back if changed
    {
        GAlexRXRegister = Register;
//        RegisterWrite(VADDRALEXSPIREG+VOFFSETALEXRXREG, Register);  // and write to it
    }
    pthread_mutex_unlock(&DefaultRegMutex);
}


//
// SetAlexRXOut(bool Enable)
// P1: sets the Alex RX output relay
// NOT USED by 7000 RF board
//
void SetAlexRXOut(bool Enable)
{
    pthread_mutex_lock(&DefaultRegMutex);
    GAlexRXOut = Enable;
    pthread_mutex_unlock(&DefaultRegMutex);
}


//
// SetAlexTXAnt(unsigned int Bits)
// P1: set the Alex TX antenna bits.
// bits=00: ant1; 01: ant2; 10: ant3; other: chooses ant1
// set bits 10-8 in Alex TX reg
// NOTE a new explicit setRXant will now be needed too from FPGA V12
//
void SetAlexTXAnt(unsigned int Bits)
{
    uint32_t Register;                                  // modified register
    pthread_mutex_lock(&DefaultRegMutex);
    Register = GAlexTXAntRegister;                         // copy original register
    Register &= 0xFCFF;                                 // turn off all affected bits

    switch(Bits)
    {
        case 0:
        case 3:
        default:
            Register |=0x0100;                          // turn on ANT1
            break;

        case 1:
            Register |=0x0200;                          // turn on ANT2
            break;

        case 2:
            Register |=0x0400;                          // turn on ANT3
            break;
    }
    if(Register != GAlexTXAntRegister)                     // write back if changed
    {
        GAlexTXAntRegister = Register;
//        RegisterWrite(VADDRALEXSPIREG+VOFFSETALEXTXREG, Register);  // and write to it
    }
    pthread_mutex_unlock(&DefaultRegMutex);
}


//
// SetAlexCoarseAttenuator(unsigned int Bits)
// P1: set the 0/10/20/30dB attenuator bits. NOT used for for 7000RF board.
// bits: 00=0dB, 01=10dB, 10=20dB, 11=30dB
// Simply store the data - NOT USED for this RF board
//
void SetAlexCoarseAttenuator(unsigned int Bits)
{
    pthread_mutex_lock(&DefaultRegMutex);
    GAlexCoarseAttenuatorBits = Bits;
    pthread_mutex_unlock(&DefaultRegMutex);
}


//
// SetAlexRXFilters(bool IsRX1, unsigned int Bits)
// P1: set the Alex bits for RX BPF filter selection
// IsRX1 true for RX1, false for RX2
// Bits follows the P1 protocol format
// RX1: C0=0x12, byte C3 has RX1;
// RX2: C0-0x12, byte X1 has RX2
//
void SetAlexRXFilters(bool IsRX1, unsigned int Bits)
{
    uint32_t Register;                                          // modified register
    pthread_mutex_lock(&DefaultRegMutex);
    if(GAlexManualFilterSelect)
    {
        Register = GAlexRXRegister;                             // copy original register
        if(IsRX1)
        {
            Register &= 0xFFFFEF81;                             // turn off all affected bits
            Register |= (Bits & 0x03)<<1;                       // bits 1-0, moved up
            Register |= (Bits & 0x1C)<<2;                       // bits 4-2, moved up
            Register |= (Bits & 0x40)>>3;                       // bit 6 moved down
            Register |= (Bits & 0x20)<<7;                       // bit 5 moved up
        }
        else
        {
            Register &= 0xEF81FFFF;                             // turn off all affected bits
            Register |= (Bits & 0x03)<<17;                      // bits 1-0, moved up
            Register |= (Bits & 0x1C)<<18;                      // bits 4-2, moved up
            Register |= (Bits & 0x40)<<13;                      // bit 6 moved up
            Register |= (Bits & 0x20)<<23;                      // bit 5 moved up
            Register |= (Bits & 0x80)<<21;                      // bit 7 moved up
        }

        if(Register != GAlexRXRegister)                     // write back if changed
        {
            GAlexRXRegister = Register;
    //        RegisterWrite(VADDRALEXSPIREG+VOFFSETALEXRXREG, Register);  // and write to it
        }
    }
    pthread_mutex_unlock(&DefaultRegMutex);
}


//
// SetRX2GroundDuringTX(bool IsGrounded)
//
void SetRX2GroundDuringTX(bool IsGrounded)
{
    pthread_mutex_lock(&DefaultRegMutex);
    GRX2GroundDuringTX = IsGrounded;
    pthread_mutex_unlock(&DefaultRegMutex);
}

//
// SetAlexTXFilters(unsigned int Bits)
// P1: set the Alex bits for TX LPF filter selection
// Bits follows the P1 protocol format. C0=0x12, byte C4 has TX
// from FPGA V12, the same data needs to go into the TXfilter/TX antenna register
// because the filter settings are in both
//
void SetAlexTXFilters(unsigned int Bits)
{
    uint32_t Register;                                          // modified register
    pthread_mutex_lock(&DefaultRegMutex);
    if(GAlexManualFilterSelect)
    {
        Register = GAlexTXFiltRegister;                         // copy original register
        Register &= 0x1F0F;                                 // turn off all affected bits
        Register |= (Bits & 0x0F)<<4;                       // bits 3-0, moved up
        Register |= (Bits & 0x1C)<<9;                      // bits 6-4, moved up

        if(Register != GAlexTXFiltRegister)                     // write back if changed
        {
            GAlexTXFiltRegister = Register;
    //        RegisterWrite(VADDRALEXSPIREG+VOFFSETALEXTXREG, Register);  // and write to it
        }

        Register = GAlexTXAntRegister;                         // copy original register
        Register &= 0x1F0F;                                 // turn off all affected bits
        Register |= (Bits & 0x0F)<<4;                       // bits 3-0, moved up
        Register |= (Bits & 0x1C)<<9;                      // bits 6-4, moved up

        if(Register != GAlexTXAntRegister)                     // write back if changed
        {
            GAlexTXAntRegister = Register;
    //        RegisterWrite(VADDRALEXSPIREG+VOFFSETALEXTXREG, Register);  // and write to it
        }
    }
    pthread_mutex_unlock(&DefaultRegMutex);
}


//
// EnableAlexManualFilterSelect(bool IsManual)
// used to select between automatic selection of filters, and remotely commanded settings.
// if Auto, the RX and TX filters are calculated when a frequency change occurs
//
void EnableAlexManualFilterSelect(bool IsManual)
{
    pthread_mutex_lock(&DefaultRegMutex);
    GAlexManualFilterSelect = IsManual;                 // just store the bit
    pthread_mutex_unlock(&DefaultRegMutex);
}


//
// AlexManualRXFilters(unsigned int Bits, int RX)
// P2: provides a 16 bit word with all of the Alex settings for a single RX
// must be formatted according to the Alex specification
// RX=0 or 1: RX1; RX=2: RX2
// must be enabled by calling EnableAlexManualFilterSelect(true) first!
//
void AlexManualRXFilters(unsigned int Bits, int RX)
{
    uint32_t Register;                                          // modified register
    pthread_mutex_lock(&DefaultRegMutex);
    if(GAlexManualFilterSelect)
    {
        Register = GAlexRXRegister;                             // copy original register
        if(RX != 2)
        {
            Register &= 0xFFFF0000;                             // turn off all affected bits
            Register |= Bits;                                   // add back all new bits
        }
        else
        {
            Register &= 0x0000FFFF;                             // turn off all affected bits
            Register |= (Bits<<16);                             // add back all new bits
        }
        if(Register != GAlexRXRegister)                     // write back if changed
        {
            GAlexRXRegister = Register;
            RegisterWrite(VADDRALEXSPIREG+VOFFSETALEXRXREG, Register);  // and write to it
        }
    }
    pthread_mutex_unlock(&DefaultRegMutex);
}


//
// DisableAlexTRRelay(bool IsDisabled)
// if parameter true, the TX RX relay is disabled and left in RX 
//
void DisableAlexTRRelay(bool IsDisabled)
{
    pthread_mutex_lock(&DefaultRegMutex);
    GEnableAlexTXRXRelay = !IsDisabled;                     // enable TXRX - opposite sense to stored bit
    pthread_mutex_unlock(&DefaultRegMutex);
}


//
// AlexManualTXFilters(unsigned int Bits)
// P2: provides a 16 bit word with all of the Alex settings for TX
// must be formatted according to the Alex specification
// must be enabled by calling EnableAlexManualFilterSelect(true) first!
// FPGA V12 onwards: uses an additional register with TX ant settings
// HasTXAntExplicitly true if data is for the new TXfilter, TX ant register
//
void AlexManualTXFilters(unsigned int Bits, bool HasTXAntExplicitly)
{
    uint32_t Register;                                  // modified register
    pthread_mutex_lock(&DefaultRegMutex);
    if(GAlexManualFilterSelect)
    {
        Register = Bits;                         // new setting
        if(HasTXAntExplicitly && (Register != GAlexTXAntRegister))
        {
            GAlexTXAntRegister = Register;
            RegisterWrite(VADDRALEXSPIREG+VOFFSETALEXTXANTREG, Register);  // and write to it
        }
        else if(!HasTXAntExplicitly &&(Register != GAlexTXFiltRegister))                     // write back if changed
        {
            GAlexTXFiltRegister = Register;
            RegisterWrite(VADDRALEXSPIREG+VOFFSETALEXTXFILTREG, Register);  // and write to it
        }
    }
    pthread_mutex_unlock(&DefaultRegMutex);
}


//
// SetApolloBits(bool EnableFilter, bool EnableATU, bool StartAutoTune)
// sets the control bits for Apollo. No support for these in Saturn at present.
//
void SetApolloBits(bool EnableFilter, bool EnableATU, bool StartAutoTune)
{
    pthread_mutex_lock(&DefaultRegMutex);
    GEnableApolloFilter = EnableFilter;
    GEnableApolloATU = EnableATU;
    GStartApolloAutoTune = StartAutoTune;
    pthread_mutex_unlock(&DefaultRegMutex);
}


//
// SetApolloEnabled(bool EnableFilter)
// sets the enabled bit for Apollo. No support for these in Saturn at present.
//
void SetApolloEnabled(bool EnableFilter)
{
    pthread_mutex_lock(&DefaultRegMutex);
    GEnableApolloFilter = EnableFilter;
    pthread_mutex_unlock(&DefaultRegMutex);
}



//
// SelectFilterBoard(bool IsApollo)
// Selects between Apollo and Alex controls. Currently ignored & hw supports only Alex.
//
void SelectFilterBoard(bool IsApollo)
{
    pthread_mutex_lock(&DefaultRegMutex);
    GIsApollo = IsApollo;
    pthread_mutex_unlock(&DefaultRegMutex);
}


//
// EnablePPSStamp(bool Enabled)
// enables a "pulse per second" timestamp
//
void EnablePPSStamp(bool Enabled)
{
    pthread_mutex_lock(&DefaultRegMutex);
    GPPSEnabled = Enabled;
    pthread_mutex_unlock(&DefaultRegMutex);
}


//
// SetTXDriveLevel(unsigned int Level)
// sets the TX DAC current via a PWM DAC output
// level: 0 to 255 drive level value (255 = max current)
// sets both step attenuator drive and PWM DAC drive for high speed DAC current,
// using ROMs calculated at initialise.
//
void SetTXDriveLevel(unsigned int Level) {
  uint32_t RegisterValue = 0;
  uint32_t DACDrive, AttenDrive;

  pthread_mutex_lock(&DefaultRegMutex);
  Level &= 0xFF;                                  // make sure 8 bits only
  DACDrive = DACCurrentROM[Level];                // get PWM
  AttenDrive = DACStepAttenROM[Level];            // get step atten
  RegisterValue = DACDrive;                       // set drive level when RX
  RegisterValue |= (DACDrive << 8);               // set drive level when TX
  RegisterValue |= (AttenDrive << 16);            // set step atten when RX
  RegisterValue |= (AttenDrive << 24);            // set step atten when TX
  GTXDACCtrl = RegisterValue;
  RegisterWrite(VADDRDACCTRLREG, RegisterValue);  // and write to it
  pthread_mutex_unlock(&DefaultRegMutex);
}


//
// SetMicBoost(bool EnableBoost)
// enables 20dB mic boost amplifier in the CODEC
// change bits in the codec register, and only write back if changed (I2C write is slow!)
//
void SetMicBoost(bool EnableBoost)
{
  pthread_mutex_lock(&CodecRegMutex);

  unsigned int Register = GCodecAnaloguePath;  // get current setting

  Register &= 0xFFFE;  // remove old mic boost bit
  if (EnableBoost)
    Register |= 1;  // set new mic boost bit

  if (Register != GCodecAnaloguePath)  // only write back if changed
  {
    GCodecAnaloguePath = Register;
    CodecRegisterWriteUnsafe(VCODECANALOGUEPATHREG, Register);
  }

  pthread_mutex_unlock(&CodecRegMutex);
}


//
// SetMicLineInput(bool IsLineIn)
// chooses between microphone and Line input to Codec
// change bits in the codec register, and only write back if changed (I2C write is slow!)
//
void SetMicLineInput(bool IsLineIn)
{
    unsigned int Register;
    pthread_mutex_lock(&CodecRegMutex);
    Register = GCodecAnaloguePath;                      // get current setting
    Register &= 0xFFFB;                                 // remove old mic / line select bit
    if(!IsLineIn)
        Register |= 4;                                  // set new select bit
    if(Register != GCodecAnaloguePath)                  // only write back if changed
    {
        GCodecAnaloguePath = Register;
        CodecRegisterWriteUnsafe(VCODECANALOGUEPATHREG, Register);
    }
    pthread_mutex_unlock(&CodecRegMutex);
}



//
// SetOrionMicOptions(bool MicRing, bool EnableBias, bool EnablePTT)
// sets the microphone control inputs
// write the bits to GPIO. Note the register bits aren't directly the protocol input bits.
// note also that EnablePTT is actually a DISABLE signal (enabled = 0)
//
void SetOrionMicOptions(bool MicRing, bool EnableBias, bool EnablePTT)
{
    uint32_t Register;                              // FPGA register content

    pthread_mutex_lock(&RFGPIOMutex);               // get protected access
    Register = GPIORegValue;                        // get current settings
    Register &= ~(UINT32_C(1) << VMICBIASENABLEBIT);          // strip old bits
    Register &= ~(UINT32_C(1) << VMICPTTSELECTBIT);           // strip old bits
    Register &= ~(UINT32_C(1) << VMICSIGNALSELECTBIT);
    Register &= ~(UINT32_C(1) << VMICBIASSELECTBIT);

    if(!MicRing)                                      // add new bits where set
    {
        Register &= ~(UINT32_C(1) << VMICSIGNALSELECTBIT);    // mic on tip
        Register |= (UINT32_C(1) << VMICBIASSELECTBIT);       // and hence mic bias on tip
        Register &= ~(UINT32_C(1) << VMICPTTSELECTBIT);       // PTT on ring
    }
    else
    {
        Register |= (UINT32_C(1) << VMICSIGNALSELECTBIT);     // mic on ring
        Register &= ~(UINT32_C(1) << VMICBIASSELECTBIT);      // bias on ring
        Register |= (UINT32_C(1) << VMICPTTSELECTBIT);        // PTT on tip
    }
    if(EnableBias)
        Register |= (UINT32_C(1) << VMICBIASENABLEBIT);
    GPTTEnabled = !EnablePTT;                       // used when PTT read back - just store opposite state

    GPIORegValue = Register;                        // store it back
    RegisterWrite(VADDRRFGPIOREG, Register);      // and write to it
    pthread_mutex_unlock(&RFGPIOMutex);             // clear protected access
}


//
// SetBalancedMicInput(bool Balanced)
// selects the balanced microphone input, not supported by current protocol code. 
// just set the bit into GPIO
//
void SetBalancedMicInput(bool Balanced)
{
    uint32_t Register;                              // FPGA register content

    pthread_mutex_lock(&RFGPIOMutex);               // get protected access
    Register = GPIORegValue;                        // get current settings
    Register &= ~(1 << VBALANCEDMICSELECT);         // strip old bit
    if(Balanced)
        Register |= (1 << VBALANCEDMICSELECT);      // set new bit
    
    GPIORegValue = Register;                        // store it back
    RegisterWrite(VADDRRFGPIOREG, Register);      // and write to it
    pthread_mutex_unlock(&RFGPIOMutex);             // clear protected access
}


//
// SetCodecLineInGain(unsigned int Gain)
// sets the line input level register in the Codec (4 bits)
// change bits in the codec register, and only write back if changed (I2C write is slow!)
//
void SetCodecLineInGain(unsigned int Gain)
{
    unsigned int Register;

    Register = GCodecLineGain;                          // get current setting

    Register &= 0xFFE0;                                 // remove old gain
    Register |= Gain;                                   // set new gain
    if(Register != GCodecLineGain)                      // only write back if changed
    {
        GCodecLineGain = Register;
        CodecRegisterWriteSingle(VCODECLLINEVOLREG, Register);
    }
}


//
// EnablePureSignal(bool Enabled)
// enables PureSignal operation. Enables DDC5 to be feedback (P1)
//
void EnablePureSignal(bool Enabled)
{
    GPureSignalEnabled = Enabled;
}


//
// SetADCAttenuator(EADCSelect ADC, unsigned int Atten, bool Enabled, bool RXAtten)
// sets the  stepped attenuator on the ADC input
// Atten provides a 5 bit atten value
// RXAtten: if true, sets atten to be used during RX
// TXAtten: if true, sets atten to be used during TX
// (it can be both!)
//
void SetADCAttenuator(EADCSelect ADC, unsigned int Atten, bool RXAtten, bool TXAtten)
{
    uint32_t Register;                              // local copy
    uint32_t TXMask;
    uint32_t RXMask;

    pthread_mutex_lock(&DefaultRegMutex);
    Register = GRXADCCtrl;                          // get existing settings
    TXMask = 0b0000001111100000;                    // mask bits for TX, ADC1
    RXMask = 0b0000000000011111;                    // mask bits for RX, ADC1
    if(ADC == eADC1)
    {
        if(RXAtten)
        {
            Register &= ~RXMask;
            Register |= (Atten & 0X1F);             // add in new bits for ADC1, RX
        }
        if(TXAtten)
        {
            Register &= ~TXMask;
            Register |= (Atten & 0X1F)<<5;          // add in new bits for ADC1, TX
        }
    }
    else
    {
        TXMask = TXMask << 10;                      // move to ADC2 bit positions
        RXMask = RXMask << 10;                      // move to ADC2 bit positions
        if(RXAtten)
        {
            Register &= ~RXMask;
            Register |= (Atten & 0X1F) << 10;       // add in new bits for ADC2, RX
        }
        if(TXAtten)
        {
            Register &= ~TXMask;
            Register |= (Atten & 0X1F)<<15;         // add in new bits for ADC2, TX
        }
    }

    GRXADCCtrl = Register;
    RegisterWrite(VADDRADCCTRLREG, Register);      // and write to it
    pthread_mutex_unlock(&DefaultRegMutex);
}



//
//void SetCWIambicKeyer(...)
// setup CW iambic keyer parameters
// Speed: keyer speed in WPM
// weight: typically 50
// ReverseKeys: swaps dot and dash
// mode: true if mode B
// strictSpacing: true if it enforces character spacing
// IambicEnabled: if false, reverts to straight CW key
//
void SetCWIambicKeyer(uint8_t Speed, uint8_t Weight, bool ReverseKeys, bool Mode, 
                      bool StrictSpacing, bool IambicEnabled, bool Breakin)
{
    uint32_t Register;
    Register = GIambicConfigReg;                    // copy of H/W register
    Register &= ~VIAMBICBITS;                       // strip off old iambic bits

    GCWKeyerSpeed = Speed;                          // just save it for now
    GCWKeyerWeight = Weight;                        // just save it for now
    GCWKeysReversed = ReverseKeys;                  // just save it for now
    GCWKeyerMode = Mode;                            // just save it for now
    GCWKeyerSpacing = StrictSpacing;
    GCWIambicKeyerEnabled = IambicEnabled;

    // set new data
    Register |= Speed;
    Register |= (Weight << VIAMBICWEIGHT);
    if(ReverseKeys)
        Register |= (1<<VIAMBICREVERSED);           // set bit if enabled
    if(Mode)
        Register |= (1<<VIAMBICMODE);               // set bit if enabled
    if(StrictSpacing)
        Register |= (1<<VIAMBICSTRICT);             // set bit if enabled
    if(IambicEnabled)
        Register |= (1<<VIAMBICENABLE);             // set bit if enabled
    if(Breakin)
        Register |= (1<<VCWBREAKIN);             // set bit if enabled

    pthread_mutex_lock(&DefaultRegMutex);
    if (Register != GIambicConfigReg)               // save if changed
    {
        GIambicConfigReg = Register;
        RegisterWrite(VADDRIAMBICCONFIG, Register);
    }
    pthread_mutex_unlock(&DefaultRegMutex);
}


//
// void SetCWXBits(bool CWXEnabled, bool CWXDash, bool CWXDot)
// setup CWX (host generated dot and dash)
//
void SetCWXBits(bool CWXEnabled, bool CWXDash, bool CWXDot)
{
    uint32_t Register;
    Register =GIambicConfigReg;                     // copy of H/W register
    Register &= ~VIAMBICCWXBITS;                    // strip off old CWX bits
    GCWXMode =CWXEnabled;                           // computer generated CWX mode
    GCWXDot = CWXDot;                               // computer generated CW Dot.
    GCWXDash = CWXDash;                             // computer generated CW Dash.
    if(GCWXMode)
        Register |= (1<<VIAMBICCWX);                // set bit if enabled
    if(GCWXDot)
        Register |= (1<<VIAMBICCWXDOT);             // set bit if enabled
    if(GCWXDash)
        Register |= (1<<VIAMBICCWXDASH);            // set bit if enabled
    pthread_mutex_lock(&DefaultRegMutex);
    if (Register != GIambicConfigReg)               // save if changed
    {
        GIambicConfigReg = Register;
        RegisterWrite(VADDRIAMBICCONFIG, Register);
    }
    pthread_mutex_unlock(&DefaultRegMutex);
}



//
// SetDDCADC(int DDC, EADCSelect ADC)
// sets the ADC to be used for each DDC
// DDC = 0 to 9
// if GADCOverride is set, set to test source instead
//
void SetDDCADC(int DDC, EADCSelect ADC)
{
    uint32_t RegisterValue;
    uint32_t ADCSetting;
    uint32_t Mask;

    if(GADCOverride)
        ADC = eTestSource;                          // override setting

    ADCSetting = ((uint32_t)ADC & 0x3) << (DDC*2);  // 2 bits with ADC setting
    Mask = 0x3 << (DDC*2);                          // 0,2,4,6,8,10,12,14,16,18bit positions

    pthread_mutex_lock(&DDCInSelMutex);             // get protected access
    RegisterValue = DDCInSelReg;                    // get current register setting
    RegisterValue &= ~Mask;                         // strip ADC bits
    RegisterValue |= ADCSetting;

    DDCInSelReg = RegisterValue;                    // write back
    RegisterWrite(VADDRDDCINSEL, RegisterValue);    // and write to it
    pthread_mutex_unlock(&DDCInSelMutex);
}



//
// void SetRXDDCEnabled(bool IsEnabled);
// sets enable bit so DDC operates normally. Resets input FIFO when starting.
//
void SetRXDDCEnabled(bool IsEnabled)
{
    uint32_t Address;									// register address
    uint32_t Data;										// register content

    Address = VADDRDDCINSEL;							// DDC config register address

    pthread_mutex_lock(&DDCInSelMutex);   // get protected access
    Data = DDCInSelReg;                   // get current register setting
    if (IsEnabled)
        Data |= (UINT32_C(1) << 30);								// set new bit
    else
        Data &= ~(UINT32_C(1) << 30);								// clear new bit

    DDCInSelReg = Data;          // write back
    RegisterWrite(Address, Data);					// write back
    pthread_mutex_unlock(&DDCInSelMutex);
}


#define VMINCWRAMPDURATION 3000                     // 3ms min
#define VMAXCWRAMPDURATION 10000                    // 10ms max
#define VMAXCWRAMPDURATIONV14PLUS 20000             // 20ms max


//
// InitialiseCWKeyerRamp(bool Protocol2, uint32_t Length_us)
// calculates an "S" shape ramp curve and loads into RAM
// needs to be called before keyer enabled!
// parameter is length in microseconds; typically 5000-10000
// setup ramp memory and ramp length fields
// only calculate if paramters have changed!
//
void InitialiseCWKeyerRamp(bool Protocol2, uint32_t Length_us)
{
    const double c1 = -0.12182865361171612;
    const double c2 = -0.018557469249199286;
    const double c3 = -0.0009378783245428506;
    const double c4 = 0.0008567571519403228;
    const double c5 = 0.00018706912431472442;


    const double twopi = 6.28318530717959;
    const double fourpi = 12.56637061435920;
    const double sixpi = 18.84955592153880;
    const double eightpi = 25.13274122871830;
    const double tenpi = 31.41592653589790;

    double LargestSample;
    double Fraction;                        // fractional position in ramp
    double SamplePeriod;                    // sample period in us
    double Length;                          // length required in us
    uint32_t RampLength;                    // integer length in WORDS not bytes!
    double RampSample[VRAMPSIZE];           // array samples
    uint32_t Cntr;
    uint32_t Sample;                        // ramp sample value
    uint32_t Register;
    unsigned int FPGAVersion = 0;
    unsigned int MaxDuration;               // max ramp duration in microseconds
    double x, x2, x4, x6, x8, x10, rampsample;

    FirmwareInfo fwInfo = GetFirmwareInfo();
    FPGAVersion = fwInfo.version;

    if(FPGAVersion >= 14)
        MaxDuration = VMAXCWRAMPDURATIONV14PLUS;        // get version dependent max length
    else
        MaxDuration = VMAXCWRAMPDURATION;

    // first find out if the length is OK and clip if not
    if(Length_us < VMINCWRAMPDURATION)
        Length_us = VMINCWRAMPDURATION;
    if(Length_us > MaxDuration)
        Length_us = MaxDuration;

    // now apply that ramp length
    if((Length_us != GCWKeyerRampms) || (Protocol2 != GCWKeyerRamp_IsP2)) 
    {
        GCWKeyerRampms = Length_us;
        GCWKeyerRamp_IsP2 = Protocol2;
        printf("calculating new CW ramp, length = %d us\n", Length_us);
    // work out required length in samples
        if(Protocol2)
            SamplePeriod = 1000.0/192.0;
        else
            SamplePeriod = 1000.0/48.0;
        RampLength = (uint32_t)(((double)Length_us / SamplePeriod) + 1);

//
// DL1YCF ramp code:
//
//
        pthread_mutex_lock(&DefaultRegMutex);
        for (Cntr = 0; Cntr < RampLength; Cntr++)
        {
            x = (double) Cntr / (double) RampLength;           // between 0 and 1
            x2 = x * twopi;         // 2 Pi x
            x4 = x * fourpi;        // 4 Pi x
            x6 = x * sixpi;         // 6 Pi x
            x8 = x * eightpi;       // 8 Pi x
            x10 = x * tenpi;        // 10 Pi x
            rampsample = x + c1 * sin(x2) + c2 * sin(x4) + c3 * sin(x6) + c4 * sin(x8) + c5 * sin(x10);
            Sample = (uint32_t) (rampsample * 8388607.0);
            RegisterWrite(VADDRCWKEYERRAM + 4*Cntr, Sample);
        }
        for(Cntr = RampLength; Cntr < VRAMPSIZE; Cntr++)                        // fill remainder of RAM
            RegisterWrite(VADDRCWKEYERRAM + 4*Cntr, 8388607);

    //
    // finally write the ramp length
    // in FPGA V14 onwards this is a word address
        Register = GCWKeyerSetup;                    // get current settings
        Register &= 0x8003FFFF;                      // strip out ramp bits
        if(FPGAVersion >= 14)
            Register |= (RampLength << VCWKEYERRAMP);        // word end address
        else
            Register |= ((RampLength << 2) << VCWKEYERRAMP);        // byte end address

        GCWKeyerSetup = Register;                    // store it back
        RegisterWrite(VADDRKEYERCONFIGREG, Register);  // and write to it
    }
    pthread_mutex_unlock(&DefaultRegMutex);
}





//
// EnableCW (bool Enabled, bool Breakin)
// enables or disables CW mode; selects CW as modulation source.
// If Breakin enabled, the key input engages TX automatically
// and generates sidetone.
//
void EnableCW(bool Enabled, bool Breakin)
{
    //
    // set I/Q modulation source if CW selected 
    //
    GCWEnabled = Enabled;
    if(Enabled)
        SetTXModulationSource(eCWKeyer);                // CW source
    else
        SetTXModulationSource(eIQData);                 // else IQ source

    // now set keyer enable if CW and break-in
    GBreakinEnabled = Breakin;
    ActivateCWKeyer(GBreakinEnabled && GCWEnabled);
}


//
// SetCWSidetoneEnabled(bool Enabled)
// enables or disables sidetone. If disabled, the volume is set to zero in codec config reg
// only do something if the bit changes; note the volume setting function is relevant too
//
void SetCWSidetoneEnabled(bool Enabled)
{
  pthread_mutex_lock(&CodecRegMutex);

  if (GSidetoneEnabled != Enabled)  // only act if bit changed
  {
    GSidetoneEnabled = Enabled;
    uint32_t Register = GCodecConfigReg;  // get current settings
    Register &= 0x0000FFFF;  // remove old volume bits
    if (Enabled)
      Register |= (GSidetoneVolume & 0xFF) << 24;  // add back new bits; resize to 16 bits
    GCodecConfigReg = Register;  // store it back

    CodecRegisterWriteUnsafe(VADDRCODECCONFIGREG, Register);
  }

  pthread_mutex_unlock(&CodecRegMutex);
}


//
// SetCWSidetoneVol(uint8_t Volume)
// sets the sidetone volume level (7 bits, unsigned)
//
void SetCWSidetoneVol(uint8_t Volume)
{
    uint32_t Register;
    pthread_mutex_lock(&DefaultRegMutex);

    if(GSidetoneVolume != Volume)                       // only act if value changed
    {
        GSidetoneVolume = Volume;                       // set new value
        Register = GCodecConfigReg;                     // get current settings
        Register &= 0x0000FFFF;                         // remove old volume bits
        if(GSidetoneEnabled)
            Register |= (GSidetoneVolume & 0xFF) << 24; // add back new bits; resize to 16 bits
        GCodecConfigReg = Register;                     // store it back
        RegisterWrite(VADDRCODECCONFIGREG, Register);   // and write to it
    }
    pthread_mutex_unlock(&DefaultRegMutex);
}


//
// SetCWPTTDelay(unsigned int Delay)
//  sets the delay (ms) before TX commences (8 bit delay value)
//
void SetCWPTTDelay(unsigned int Delay)
{
    uint32_t Register;
    pthread_mutex_lock(&DefaultRegMutex);

    Register = GCWKeyerSetup;                           // get current settings
    Register &= 0xFFFFFF00;                             // remove old bits
    Register |= (Delay &0xFF);                          // add back new bits
    if(Register != GCWKeyerSetup)                       // write back if different
    {
        GCWKeyerSetup = Register;                       // store it back
        RegisterWrite(VADDRKEYERCONFIGREG, Register);   // and write to it
    }
    pthread_mutex_unlock(&DefaultRegMutex);
}


//
// SetCWHangTime(unsigned int HangTime)
// sets the delay (ms) after CW key released before TX removed
// (10 bit hang time value)
//
void SetCWHangTime(unsigned int HangTime)
{
    uint32_t Register;

  pthread_mutex_lock(&DefaultRegMutex);
    Register = GCWKeyerSetup;                           // get current settings
    Register &= 0xFFFC00FF;                             // remove old bits
    Register |= (HangTime &0x3FF) << VCWKEYERHANG;      // add back new bits
    if(Register != GCWKeyerSetup)                       // write back if different
    {
        GCWKeyerSetup = Register;                       // store it back
        RegisterWrite(VADDRKEYERCONFIGREG, Register);   // and write to it
    }
  pthread_mutex_unlock(&DefaultRegMutex);
}

#define VCODECSAMPLERATE 48000                      // I2S rate
//
// SetCWSidetoneFrequency(unsigned int Frequency)
// sets the CW audio sidetone frequency, in Hz
// (12 bit value)
// DDS needs a 16 bit phase word; sample rate = 48KHz so convert accordingly
//
void SetCWSidetoneFrequency(unsigned int Frequency)
{
    uint32_t Register;
    uint32_t DeltaPhase;                                // DDS delta phase value
    double fDeltaPhase;                                 // delta phase as a float

    fDeltaPhase = 65536.0 * (double)Frequency / (double) VCODECSAMPLERATE;
    DeltaPhase = ((uint32_t)fDeltaPhase) & 0xFFFF;

    Register = GCodecConfigReg;                         // get current settings
    Register &= 0xFFFF0000;                             // remove old bits
    Register |= DeltaPhase;                             // add back new bits

    if(Register != GCodecConfigReg)                     // write back if different
    {
        GCodecConfigReg = Register;                     // store it back
        RegisterWrite(VADDRCODECCONFIGREG, Register);   // and write to it
    }
}


//
// SetMinPWMWidth(unsigned int Width)
// set class E min PWM width (not yet implemented)
//
void SetMinPWMWidth(unsigned int Width)
{
    GClassEPWMMin = Width;                                      // just store for now
}


//
// SetMaxPWMWidth(unsigned int Width)
// set class E min PWM width (not yet implemented)
//
void SetMaxPWMWidth(unsigned int Width)
{
    GClassEPWMMax = Width;                                      // just store for now
}


//
// SetXvtrEnable(bool Enabled)
// enables or disables transverter. If enabled, the PA is not keyed.
//
void SetXvtrEnable(bool Enabled) {
  uint32_t Register;

  pthread_mutex_lock(&RFGPIOMutex);               // get protected access
  Register = GPIORegValue;                        // get current settings
  if (Enabled) {
    Register |= (UINT32_C(1) << VXVTRENABLEBIT);
  } else {
    Register &= ~(UINT32_C(1) << VXVTRENABLEBIT);
  }
  GPIORegValue = Register;                    // store it back
  pthread_mutex_unlock(&RFGPIOMutex);         // clear protected access
}


//
// SetWidebandEnable(EADCSelect ADC, bool Enabled)
// enables wideband sample collection from an ADC.
// P2 - not yet implemented
//
void SetWidebandEnable(EADCSelect ADC, bool Enabled)
{
    if(ADC == eADC1)                        // if ADC1 save its state
        GWidebandADC1 = Enabled; 
    else if(ADC == eADC2)                   // similarly for ADC2
        GWidebandADC2 = Enabled; 

}


//
// SetWidebandSampleCount(unsigned int Samples)
// sets the wideband data collected count
// P2 - not yet implemented
//
void SetWidebandSampleCount(unsigned int Samples)
{
    GWidebandSampleCount = Samples;
}


//
// SetWidebandSampleSize(unsigned int Bits)
// sets the sample size per packet used for wideband data transfers
// P2 - not yet implemented
//
void SetWidebandSampleSize(unsigned int Bits)
{
    GWidebandSamplesPerPacket = Bits;
}


//
// SetWidebandUpdateRate(unsigned int Period_ms)
// sets the period (ms) between collections of wideband data
// P2 - not yet implemented
//
void SetWidebandUpdateRate(unsigned int Period_ms)
{
    GWidebandUpdateRate = Period_ms;
}


//
// SetWidebandPacketsPerFrame(unsigned int Count)
// sets the number of packets to be transferred per wideband data frame
// P2 - not yet implemented
//
void SetWidebandPacketsPerFrame(unsigned int Count)
{
    GWidebandPacketsPerFrame = Count;
}


//
// EnableTimeStamp(bool Enabled)
// enables a timestamp for RX packets
//
void EnableTimeStamp(bool Enabled)
{
    GEnableTimeStamping = Enabled;                          // P2. true if enabled. NOT SUPPORTED YET
}


//
// EnableVITA49(bool Enabled)
// enables VITA49 mode
//
void EnableVITA49(bool Enabled)
{
    GEnableVITA49 = Enabled;                                // P2. true if enabled. NOT SUPPORTED YET
}


//
// SetAlexEnabled(unsigned int Alex)
// 8 bit parameter enables up to 8 Alex units.
//
void SetAlexEnabled(unsigned int Alex)
{
    GAlexEnabledBits = Alex;                                // just save for now.
}


//
// SetPAEnabled(bool Enabled)
// true if PA is enabled. 
//
void SetPAEnabled(bool Enabled)
{
    uint32_t Register;

    GPAEnabled = Enabled;                           // just save for now
    pthread_mutex_lock(&RFGPIOMutex);               // get protected access
    Register = GPIORegValue;                        // get current settings
    if(!Enabled)
        Register |= (1<<VTXRELAYDISABLEBIT);
    else
        Register &= ~(1<<VTXRELAYDISABLEBIT);
    GPIORegValue = Register;                    // store it back
    RegisterWrite(VADDRRFGPIOREG, Register);  // and write to it
    pthread_mutex_unlock(&RFGPIOMutex);         // clear protected access
}


//
// SetTXDACCount(unsigned int Count)
// sets the number of TX DACs, Currently unused. 
//
void SetTXDACCount(unsigned int Count)
{
    GTXDACCount = Count;                                    // just save for now.
}


//
// SetDUCSampleRate(ESampleRate Rate)
// sets the DUC sample rate. 
// current Saturn h/w supports 48KHz for protocol 1 and 192KHz for protocol 2
//
void SetDUCSampleRate(ESampleRate Rate)
{
    GDUCSampleRate = Rate;                                  // just save for now.
}


//
// SetDUCSampleSize(unsigned int Bits)
// sets the number of bits per sample.
// currently unimplemented, and protocol 2 always uses 24 bits per sample.
//
void SetDUCSampleSize(unsigned int Bits)
{
    GDUCSampleSize = Bits;                                  // just save for now
}


//
// SetDUCPhaseShift(unsigned int Value)
// sets a phase shift onto the TX output. Currently unimplemented. 
//
void SetDUCPhaseShift(unsigned int Value)
{
    GDUCPhaseShift = Value;                                 // just save for now. 
}



//
// SetSpkrMute(bool IsMuted)
// enables or disables the Codec speaker output
//
void SetSpkrMute(bool IsMuted)
{
    uint32_t Register;

    GSpeakerMuted = IsMuted;                        // just save for now.

    pthread_mutex_lock(&RFGPIOMutex);               // get protected access
    Register = GPIORegValue;                        // get current settings
    if(IsMuted)
        Register |= (1<<VSPKRMUTEBIT);
    else
        Register &= ~(1<<VSPKRMUTEBIT);
    GPIORegValue = Register;                        // store it back
    RegisterWrite(VADDRRFGPIOREG, Register);        // and write to it
    pthread_mutex_unlock(&RFGPIOMutex);             // clear protected access
}


//
// SetUserOutputBits(unsigned int Bits)
// sets the user I/O bits
//
void SetUserOutputBits(unsigned int Bits)
{
    GUserOutputBits = Bits;                         // just save for now
}


/////////////////////////////////////////////////////////////////////////////////
// read settings from FPGA
//

//
// ReadStatusRegister(void)
// this is a precursor to getting any of the data itself; simply reads the register to a local variable
// probably call every time an outgoing packet is put together initially
// but possibly do this one a timed basis.
//
inline void ReadStatusRegister(void) {
  pthread_mutex_lock(&DefaultRegMutex);
  uint32_t StatusRegisterValue = RegisterRead(VADDRSTATUSREG);
  GStatusRegister = StatusRegisterValue;                  // save to global
  pthread_mutex_unlock(&DefaultRegMutex);
}


inline uint32_t ReadChannelStatusRegister(int Channel) {
  uint32_t data;
  pthread_mutex_lock(&DefaultRegMutex);
  data = ReadChannelStatusRegisterUnsafe(Channel);
  pthread_mutex_unlock(&DefaultRegMutex);
  return data;
}


inline uint32_t ReadChannelStatusRegisterUnsafe(int Channel) {
  uint32_t address = VADDRFIFOMONBASE + 4 * (uint32_t)Channel;
  return RegisterRead(address);
}


inline uint32_t ReadChannelStatusAndUpdateFIFODepth(EDMAStreamSelect Channel, uint32_t* FIFODepth) {
  uint32_t status;
  status = ReadChannelStatusRegister(Channel);
  if (FIFODepth != NULL) {
    *FIFODepth = DMAFIFODepths[Channel];
  }
  return status;
}


inline void WriteFIFOConfigRegister(const EDMAStreamSelect *Channel, bool EnableInterrupt) {
  uint32_t Data;
  uint32_t Address;
  pthread_mutex_lock(&DefaultRegMutex);
  Address = VADDRFIFOMONBASE + 4 * (*Channel) + 0x10;      // config register address
  Data = DMAFIFODepths[(int) (*Channel)];              // memory depth
  if (EnableInterrupt)
    Data += 0x80000000;            // bit 31
  RegisterWrite(Address, Data);
  pthread_mutex_unlock(&DefaultRegMutex);
}

//
// GetPTTInput(void)
// return true if PTT input is pressed.
// depends on the status register having been read before this is called!
//
bool GetPTTInput(void) {
  pthread_mutex_lock(&DefaultRegMutex);
  bool result = (bool) (GStatusRegister & 1);
  pthread_mutex_unlock(&DefaultRegMutex);
  return result;
}


//
// GetKeyerDashInput(void)
// return true if keyer dash input is pressed.
// depends on the status register having been read before this is called!
//
bool GetKeyerDashInput(void) {
  pthread_mutex_lock(&DefaultRegMutex);
  bool result = (bool) ((GStatusRegister >> VKEYINB) & 1);
  pthread_mutex_unlock(&DefaultRegMutex);
  return result;
}



//
// GetKeyerDotInput(void)
// return true if keyer dot input is pressed.
// depends on the status register having been read before this is called!
//
bool GetKeyerDotInput(void) {
  pthread_mutex_lock(&DefaultRegMutex);
  bool result = (bool) ((GStatusRegister >> VKEYINA) & 1);
  pthread_mutex_unlock(&DefaultRegMutex);
  return result;
}


//
// GetCWKeyDown(void)
// return true if keyer has initiated TX.
// depends on the status register having been read before this is called!
//
bool GetCWKeyDown(void) {
  pthread_mutex_lock(&DefaultRegMutex);
  bool result = (bool) ((GStatusRegister >> VCWKEYDOWN) & 1);
  pthread_mutex_unlock(&DefaultRegMutex);
  return result;
}


//
// GetP2PTTKeyInputs(void)
// return several bits from Saturn status register:
// bit 0 - true if PTT active or CW keyer active
// bit 1 - true if CW dot input active
// bit 2 - true if CW dash input active or IO8 active
// bit 4 - true if 10MHz to 122MHz PLL is locked
// note that PTT declared if PTT pressed, or CW key is pressed.
// note that PTT & key bits are inverted by hardware, but IO4/5/6/8 are not.
//
unsigned int GetP2PTTKeyInputs(void)
{
  unsigned int statusRegister;

  pthread_mutex_lock(&DefaultRegMutex);
  statusRegister = GStatusRegister;
  pthread_mutex_unlock(&DefaultRegMutex);

  unsigned int result = 0;
  if (statusRegister & 1)
    result |= 1;
  if ((statusRegister >> VCWKEYDOWN) & 1)
    result |= 1;
  if ((statusRegister >> VKEYINA) & 1)
    result |= 2;
  if ((statusRegister >> VKEYINB) & 1)
    result |= 4;
  if (!((statusRegister >> VUSERIO8) & 1))
    result |= 4;
  if ((statusRegister >> VPLLLOCKED) & 1)
    result |= 16;

  return result;
}



//
// GetADCOverflow(void)
// return true if ADC amplitude overflow has occurred since last read.
// the overflow stored state is reset when this is read.
// returns bit0: 1 if ADC1 overflow; bit1: 1 if ARC2 overflow
//
unsigned int GetADCOverflow(void) {
  unsigned int result;
  pthread_mutex_lock(&DefaultRegMutex);
  result = RegisterRead(VADDRADCOVERFLOWBASE) & 0x3;
  pthread_mutex_unlock(&DefaultRegMutex);
  return result;
}



//
// GetUserIOBits(void)
// return the user input bits
// returns IO4 in LSB, IO5 in bit 1, ATU bit in bit 2 & IO8 in bit 3
//
unsigned int GetUserIOBits(void) {
  unsigned int statusRegister;

  pthread_mutex_lock(&DefaultRegMutex);
  statusRegister = GStatusRegister;
  pthread_mutex_unlock(&DefaultRegMutex);

  unsigned int result = ((statusRegister >> VUSERIO4) & 0b1011);  // get user input 4/5/-/8
  result ^= 0x8;  // invert IO8 (should be active low)
  result |= ((statusRegister >> 7) & 0b0100);  // get ATU bit into IO6 location

  return result;
}



//
// unsigned int GetAnalogueIn(unsigned int AnalogueSelect)
// return one of 6 ADC values from the RF board analogue values
// the parameter selects which input is read.
// AnalogueSelect=0: AIN1 .... AnalogueSepect=5: AIN6
unsigned int GetAnalogueIn(unsigned int AnalogueSelect) {
  AnalogueSelect &= 7;  // limit to 3 bits

  pthread_mutex_lock(&DefaultRegMutex);
  unsigned int result = RegisterRead(VADDRALEXADCBASE + 4 * AnalogueSelect);
  pthread_mutex_unlock(&DefaultRegMutex);

  return result;
}


//////////////////////////////////////////////////////////////////////////////////
// internal App register settings
// these are things not accessible from external SDR applications, including debug
//




//
// CodecInitialise(void)
// initialise the CODEC, with the register values that don't normally change
// these are the values used by existing HPSDR FPGA firmware
//
void CodecInitialise(void)
{
  GCodecLineGain = 0; // Codec left line in gain register
  GCodecAnaloguePath = 0x14; // Codec analogue path register (mic input, no boost)

  const CodecRegisterOp initOps[] = {
      {VCODECRESETREG, 0x0}, // reset register: reset device
      {VCODECACTIVATIONREG, 0x1}, // digital activation set to ACTIVE
      {VCODECANALOGUEPATHREG, GCodecAnaloguePath}, // mic input, no boost
      {VCODECPOWERDOWNREG, 0x0}, // all elements powered on
      {VCODECDIGITALFORMATREG, 0x2}, // slave; no swap; right when LRC high; 16 bit, I2S
      {VCODECSAMPLERATEREG, 0x0}, // no clock divide; rate ctrl=0; normal mode, oversample 256Fs
      {VCODECDIGITALPATHREG, 0x0}, // no soft mute; no deemphasis; ADC high pss filter enabled
      {VCODECLLINEVOLREG, GCodecLineGain}, // line in gain=0
      {VCODECRLINEVOLREG, GCodecLineGain} // line in gain=0
  };

  CodecRegisterWriteBatch(initOps, sizeof(initOps) / sizeof(initOps[0]));
}


//
// SetTXAmplitudeScaling (unsigned int Amplitude)
// sets the overall TX amplitude. This is normally set to a constant determined during development.
// 
void SetTXAmplitudeScaling(unsigned int Amplitude) {
  pthread_mutex_lock(&DefaultRegMutex);
  uint32_t Register;

  GTXAmplScaleFactor = Amplitude;                             // save value
  Register = TXConfigRegValue;                                // get current settings
  Register &= 0xFFC0000F;                                     // remove old bits
  Register |= ((Amplitude & 0x3FFFF) << VTXCONFIGSCALEBIT);   // add new bits
  TXConfigRegValue = Register;                                // store it back
  RegisterWrite(VADDRTXCONFIGREG, Register);                  // and write to it
  pthread_mutex_unlock(&DefaultRegMutex);
}



//
// SetTXProtocol (bool Protocol)
// sets whether TX configured for P1 (48KHz) or P2 (192KHz)
// true for P2
void SetTXProtocol(bool Protocol) {
  uint32_t Register;
  pthread_mutex_lock(&DefaultRegMutex);
  GTXProtocolP2 = Protocol;                           // save value
  Register = TXConfigRegValue;                        // get current settings
  Register &= 0xFFFFFF7;                              // remove old bit
  Register |= ((((unsigned int) Protocol) & 1) << VTXCONFIGPROTOCOLBIT);            // add new bit
  TXConfigRegValue = Register;                    // store it back
  RegisterWrite(VADDRTXCONFIGREG, Register);  // and write to it
  pthread_mutex_unlock(&DefaultRegMutex);
}


//
// void ResetDUCMux(void)
// resets to 64 to 48 bit multiplexer to initial state, expecting 1st 64 bit word
// also causes any input data to be discarded, so don't set it for long!
//
void ResetDUCMux(void) {
  uint32_t Register;
  uint32_t BitMask;

  pthread_mutex_lock(&DefaultRegMutex);

  BitMask = (UINT32_C(1) << 29);
  Register = TXConfigRegValue;                        // get current settings
  Register |= BitMask;                                // set reset bit
  RegisterWrite(VADDRTXCONFIGREG, Register);          // and write to it
  Register &= ~BitMask;                               // remove old bit
  RegisterWrite(VADDRTXCONFIGREG, Register);          // and write to it
  pthread_mutex_unlock(&DefaultRegMutex);
}


//
// void SetTXOutputGate(bool AlwaysOn)
// sets the sample output gater. If false, samples gated by TX strobe.
// if true, samples are alweays enabled.
//
void SetTXOutputGate(bool AlwaysOn) {
  uint32_t Register;
  uint32_t BitMask;

  pthread_mutex_lock(&DefaultRegMutex);

  GTXAlwaysEnabled = AlwaysOn;
  BitMask = (UINT32_C(1) << 2);
  Register = TXConfigRegValue;                        // get current settings
  if (AlwaysOn) {
    Register |= BitMask;                            // set bit if true
  } else {
    Register &= ~BitMask;                           // clear bit if false
  }
  TXConfigRegValue = Register;                    // store it back
  RegisterWrite(VADDRTXCONFIGREG, Register);  // and write to it
  pthread_mutex_unlock(&DefaultRegMutex);
}


//
// void SetTXIQDeinterleave(bool Interleaved)
// if true, put DUC hardware in EER mode. Alternate IQ samples go:
// even samples to I/Q modulation; odd samples to EER.
// ensure FIFO empty & reset multiplexer when changing this bit!
// shgould be called by the TX I/Q data handler only to be sure
// of meeting that constraint 
//
void SetTXIQDeinterleaved(bool Interleaved) {
  uint32_t Register;
  uint32_t BitMask;

  pthread_mutex_lock(&DefaultRegMutex);

  GTXIQInterleaved = Interleaved;
  BitMask = (UINT32_C(1) << 30);
  Register = TXConfigRegValue;                        // get current settings
  if (Interleaved)
    Register |= BitMask;                            // set bit if true
  else
    Register &= ~BitMask;                           // clear bit if false
  TXConfigRegValue = Register;                    // store it back
  RegisterWrite(VADDRTXCONFIGREG, Register);    // and write to it
  pthread_mutex_unlock(&DefaultRegMutex);
}


//
// void EnableDUCMux(bool Enabled)
// enabled the multiplexer to take samples from FIFO and hand on to DUC
// // needs to be stoppable if there is an error condition
//
void EnableDUCMux(bool Enabled) {
  uint32_t Register;
  uint32_t BitMask;
  pthread_mutex_lock(&DefaultRegMutex);

  GTXDUCMuxActive = Enabled;
  BitMask = (UINT32_C(1) << 31);
  Register = TXConfigRegValue;                        // get current settings
  if (Enabled)
    Register |= BitMask;                            // set bit if true
  else
    Register &= ~BitMask;                           // clear bit if false
  TXConfigRegValue = Register;                    // store it back
  RegisterWrite(VADDRTXCONFIGREG, Register);    // and write to it
  pthread_mutex_unlock(&DefaultRegMutex);
}




//
// SetTXModulationTestSourceFrequency (unsigned int Freq)
// sets the TX modulation DDS source frequency. Only used for development.
// 
void SetTXModulationTestSourceFrequency(unsigned int Freq) {
  uint32_t Register;
  pthread_mutex_lock(&DefaultRegMutex);

  Register = Freq;                        // get current settings
  if (Register != TXModulationTestReg)                    // write back if different
  {
    TXModulationTestReg = Register;                    // store it back
    RegisterWrite(VADDRTXMODTESTREG, Register);  // and write to it
  }
  pthread_mutex_unlock(&DefaultRegMutex);
}


//
// SetTXModulationSource(ETXModulationSource Source)
// selects the modulation source for the TX chain.
// this will need to be called operationally to change over between CW & I/Q
//
void SetTXModulationSource(ETXModulationSource Source) {
  uint32_t Register;
  pthread_mutex_lock(&DefaultRegMutex);

  GTXModulationSource = Source;                       // save value
  Register = TXConfigRegValue;                        // get current settings
  Register &= 0xFFFFFFFC;                             // remove old bits
  Register |= ((unsigned int) Source);                 // add new bits
  TXConfigRegValue = Register;                    // store it back
  RegisterWrite(VADDRTXCONFIGREG, Register);  // and write to it
  pthread_mutex_unlock(&DefaultRegMutex);
}






//
// SetDuplex(bool Enabled)
// if Enabled, the RX signal is transferred back during TX; else TX drive signal
//
void SetDuplex(bool Enabled)
{

}


//
// SetOperateMode(bool IsRunMode)
// enables or disables operation & data transfer.
//
void SetOperateMode(bool IsRunMode)
{

}


//
// SetFreqPhaseWord(bool IsPhase)
// for protocol 2, sets whether DDC/DUC frequency is phase word or frequency in Hz.
//
void SetFreqPhaseWord(bool IsPhase)
{
    
}



// SetDDCSampleSize(unsigned int DDC, unsgned int Size)
// set sample resolution for DDC (only 24 bits supported, so ignore)
//
void SetDDCSampleSize(unsigned int DDC, unsigned int Size)
{

}


//
// UseTestDDSSource(void)
// override ADC1 and ADC2 selection; use test source instead.
//
void UseTestDDSSource(void) {
  pthread_mutex_lock(&DDCInSelMutex);
  GADCOverride = true;
  DDCInSelReg = (DDCInSelReg & 0x40000000) | 0x000AAAAA;      // set all to test
  pthread_mutex_unlock(&DDCInSelMutex);
}

//
// 8 bit Codec register write over the AXILite bus via simple SPI writer IP
// given 7 bit register address and 9 bit data
//
void CodecRegisterWriteBatch(const CodecRegisterOp* ops, size_t count) {
  pthread_mutex_lock(&CodecRegMutex);
  for (size_t i = 0; i < count; i++) {
    CodecRegisterWriteUnsafe(ops[i].address, ops[i].data);
    if (i < count - 1) {
      usleep(100);  // Sleep between writes, but not after the last one
    }
  }
  pthread_mutex_unlock(&CodecRegMutex);
}

void CodecRegisterWriteSingle(uint32_t address, uint32_t data) {
  pthread_mutex_lock(&CodecRegMutex);
  CodecRegisterWriteUnsafe(address, data);
  pthread_mutex_unlock(&CodecRegMutex);
}

inline void CodecRegisterWriteUnsafe(uint32_t address, uint32_t data) {
  uint32_t writeData = (address << 9) | (data & 0x01FFUL);
  RegisterWrite(VADDRCODECSPIREG, writeData);
}

static uint32_t ReadSoftwareInformationRegister(void)
{
  pthread_mutex_lock(&DefaultRegMutex);
  uint32_t softwareInformation = RegisterRead(VADDRSWVERSIONREG);
  pthread_mutex_unlock(&DefaultRegMutex);
  return softwareInformation;
}

FirmwareInfo GetFirmwareInfo(void)
{
  uint32_t softwareInformation = ReadSoftwareInformationRegister();

  FirmwareInfo info;
  info.version = (softwareInformation >> 4) & 0xFFFF;  // 16 bit sw version
  info.id = (ESoftwareID)(softwareInformation >> 20);  // 12 bit software ID
  info.clockInfo = (softwareInformation & 0xF);

  return info;
}


float GetDieTemperatureCelcius() {
  uint32_t RegisterValue;
  float Temp;
  pthread_mutex_lock(&DefaultRegMutex);
  RegisterValue = RegisterRead(VADDRXADCTEMPREG);
  pthread_mutex_unlock(&DefaultRegMutex);
  Temp = (float)RegisterValue * 503.975f;
  Temp = Temp / 65536.0f;
  Temp -= 273.15f;
  return Temp;
}