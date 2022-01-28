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


#include "saturnregisters.h"
#include "hwaccess.h"                   // low level access
#include <stdlib.h>                     // for function min()
#include <math.h>


//
// ROMs for DAC Current Setting and 0.5dB step digital attenuator
//
unsigned int DACCurrentROM[256];                    // used for residual attenuation
unsigned int DACStepAttenROM[256];                  // provides most atten setting


//
// local copies of values written to registers
//
#define VNUMP1DDCS 5                                // DDCs used for P1
#define VSAMPLERATE 122880000                       // sample rate in Hz

uint32_t DDCDeltaPhase[VNUMDDC];                    // DDC frequency settings
uint32_t DUCDeltaPhase;                             // DUC frequency setting
uint32_t GStatusRegister;                           // most recent status register setting
uint32_t GPIORegValue;                              // value stored into GPIO
uint32_t TXConfigRegValue;                          // value written into TX config register


bool GPTTEnabled;                                   // true if PTT is enabled
bool GPureSignalEnabled;                            // true if PureSignal is enabled
ESampleRate P1SampleRate;                           // rate for all DDC
ESampleRate P2DDCSampleRate[VNUMDDC];               // array for all DDCs
uint32_t DDCConfigReg[VNUMDDC/2];                   // config registers
bool GClassESetting;                                // NOT CURRENTLY USED - true if class E operation
bool GIsApollo;                                     // NOT CURRENTLY USED - true if Apollo filter selected
bool GEnableApolloFilter;                           // Apollo filter bit - NOT USED
bool GEnableApolloATU;                              // Apollo ATU bit - NOT USED
bool GStartApolloAutoTune;                          // Start Apollo tune bit - NOT USED
bool GPPSEnabled;                                   // NOT CURRENTLY USED - trie if PPS generation enabled
uint32_t GTXDACCtrl;                                // TX DAC current setting & atten
uint32_t GRXADCCtrl;                                // RX1 & 2 attenuations
bool GAlexRXOut;                                    // P1 RX output bit (NOT USED)
uint32_t GAlexTXRegister;                           // 16 bit used of 32 
uint32_t GAlexRXRegister;                           // 32 bit RX register 
bool GRX2GroundDuringTX;                            // true if RX2 grounded while in TX
uint32_t GAlexCoarseAttenuatorBits;                 // Alex coarse atten NOT USED  
bool GAlexManualFilterSelect;                       // true if manual (remote CPU) filter setting
bool GEnableAlexTXRXRelay;                          // true if TX allowed
bool GCWKeysReversed;                               // true if keys reversed. Not yet used but will be
bool GCWKeyerBreakIn;                               // true if full break-in
unsigned int GCWKeyerSpeed;                         // Keyer speed in WPM. Not yet used
unsigned int GCWKeyerMode;                          // Keyer Mode. True if mode B. Not yet used
unsigned int GCWKeyerWeight;                        // Keyer Weight. Not yet used
bool GCWKeyerSpacing;                               // Keyer spacing
bool GCWKeyerEnabled;                               // true if iambic keyer is enabled
uint32_t GCWKeyerSetup;                             // keyer control register
uint32_t GKeyerSidetoneVol;                         // sidetone volume for CW TX
bool GCWBreakInEnabled;                             // true if full break-in enabled
uint32_t GClassEPWMMin;                             // min class E PWM. NOT USED at present.
uint32_t GClassEPWMMax;                             // max class E PWM. NOT USED at present.
uint32_t GCodecConfigReg;                           // codec configuration
bool GSidetoneEnabled;                              // true if sidetone is enabled
unsigned int GSidetoneVolume;                       // assigned sidetone volume (8 bit signed)
bool GWidebandADC1;                                 // true if wideband on ADC1. For P2 - not used yet.
bool GWidebandADC2;                                 // true if wideband on ADC2. For P2 - not used yet.
unsigned int GWidebandSampleCount;                  // P2 - not used yet
unsigned int GWidebandSamplesPerPacket;             // P2 - not used yet
unsigned int GWidebandUpdateRate;                   // update rate in ms. P2 - not used yet. 
unsigned int GWidebandPacketsPerFrame;              // P2 - not used yet
unsigned int GAlexEnabledBits;                      // P2. True if Alex1-8 enabled. NOT USED YET.
bool GPAEnabled;                                    // P2. True if PA enabled. NOT USED YET.
unsigned int GTXDACCount;                           // P2. #TX DACs. NOT USED YET.
ESampleRate GDUCSampleRate;                         // P2. TX sample rate. NOT USED YET.
unsigned int GDUCSampleSize;                        // P2. DUC # sample bits. NOT USED YET
unsigned int GDUCPhaseShift;                        // P2. DUC phase shift. NOT USED YET.
bool GSpeakerMuted;                                 // P2. True if speaker muted.
bool GCWXMode;                                      // P2. Not yet used. 
bool GDashPressed;                                  // P2. True if dash input pressed.
bool GDotPressed;                                   // P2. true if dot input pressed.
unsigned int GUserOutputBits;                       // P2. Not yet implermented.
unsigned int GTXAmplScaleFactor;                    // values multipled into TX output after DUC
ETXModulationSource GTXModulationSource;            // values added to register
bool GTXProtocolP2;                                 // true if P2
uint32_t TXModulationTestReg;                       // modulation test DDS
bool GEnableTimeStamping;                           // true if timestamps to be added to data. NOT IMPLEMENTED YET
bool GEnableVITA49;                                 // true if tyo enable VITA49 formatting. NOT SUPPORTED YET

unsigned int DACCurrentROM[256];                    // used for residual attenuation
unsigned int DACStepAttenROM[256];                  // provides most atten setting
unsigned int GNumADCs;                              // count of ADCs available


//
// local copies of Codec registers
//
unsigned int GCodecLineGain;                        // value written in Codec left line in gain register
unsigned int GCodecAnaloguePath;                    // value written in Codec analogue path register


//
// mic, bias & PTT bits in GPIO register:
//
#define VMICBIASENABLEBIT 0                         // GPIO bit definition
#define VMICPTTSELECTBIT 1                          // GPIO bit definition
#define VMICSIGNALSELECTBIT 2                       // GPIO bit definition
#define VMICBIASSELECTBIT 3                         // GPIO bit definition


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
// FPGA register map
//
#define VADDRDDC0REG 0x0
#define VADDRDDC1REG 0x4
#define VADDRDDC2REG 0xC
#define VADDRDDC3REG 0x10
#define VADDRDDC4REG 0x18
#define VADDRDDC5REG 0x1C
#define VADDRDDC6REG 0x24
#define VADDRDDC7REG 0x28
#define VADDRDDC8REG 0x30
#define VADDRDDC9REG 0x34
#define VADDRDDC0_1CONFIG 0x08
#define VADDRDDC2_3CONFIG 0x14
#define VADDRDDC4_5CONFIG 0x20
#define VADDRDDC6_7CONFIG 0x2C
#define VADDRDDC8_9CONFIG 0x38
#define VADDRRXTESTDDSREG 0X3C
#define VADDRKEYERCONFIGREG 0x40
#define VADDRCODECCONFIGREG 0x44
#define VADDRTXCONFIGREG 0x48
#define VADDRTXDUCREG 0x4C
#define VADDRTXMODTESTREG 0x50
#define VADDRRFGPIOREG 0x54
#define VADDRADCCTRLREG 0x58
#define VADDRDACCTRLREG 0x5C
#define VADDRDEBUGLEDREG 0x100
#define VADDRSTATUSREG 0x1000
#define VADDRUSERVERSIONREG 0x1004              // user defined version register
#define VADDRADCOVERFLOWBASE 0x2000
#define VADDRFIFOMON0BASE 0x3000
#define VADDRFIFOMON1BASE 0x3000
#define VADDRFIFOMON2BASE 0x3000
#define VADDRFIFOMON3BASE 0x3000
#define VADDRALEXADCBASE 0x4000
#define VADDRCWKEYERRAM 0x5000
#define VADDRALEXSPIREG 0x1C000
#define VADDRCONFIGSPIREG 0x10000
#define VADDRCODECI2CREG 0x14000
#define VADDRXADCREG 0x18000                    // on-chip ADC



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
  VADDRDDC9REG,
};

uint32_t DDCConfigRegs[VNUMDDC] = 
{
  VADDRDDC0_1CONFIG,                            // 0 & 1
  VADDRDDC0_1CONFIG, 
  VADDRDDC2_3CONFIG,                            // 2 & 3
  VADDRDDC2_3CONFIG,
  VADDRDDC4_5CONFIG,                            // 4 & 5
  VADDRDDC4_5CONFIG,
  VADDRDDC6_7CONFIG,                            // 6 & 7
  VADDRDDC6_7CONFIG,
  VADDRDDC8_9CONFIG,                            // 8 & 9
  VADDRDDC8_9CONFIG
};

//
// ALEX SPI registers
//
#define VOFFSETALEXTXREG 0                              // offset addr in IP core
#define VOFFSETALEXRXREG 4                              // offset addr in IP core


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
#define VUSERIO6 8
#define VUSERIO8 7
#define V13_8VDETECTBIT 8
#define VATUTUNECOMPLETEBIT 9
#define VEXTTXENABLEBIT 31


//
// Keyer setup register defines
//
#define VCWKEYERENABLE 31                               // enble bit
#define VCWKEYERHANG 8                                  // hang time is 17:8
#define VCWKEYERRAMP 18                                 // ramp time


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



//
// initialise the DAC Atten ROMs
// these set the step attenuator and DAC drive level
// for "attenuation intent" values from 0 to 255
//
void InitialiseDACAttenROMs(void)
{
    unsigned int Level;                         // input demand value
    double DesiredAtten;                        // desired attenuation in dB
    double StepAtten;                           // step attenuation in 0.5dB steps
    unsigned int StepValue;                     // integer step atten drive value
    double ResidualAtten;                       // atten to go in the current setting DAC
    unsigned int DACDrive;                      // int value to go to DAC ROM

//
// do the max atten values separately; then calculate point by point
//
    DACCurrentROM[0] = 0;                       // min level
    DACStepAttenROM[0] = 63;                    // max atten

    for (Level = 1; Level < 255; Level++)
    {
        DesiredAtten = 20.0*log10(255/Level);   // this is the atten value we want after the high speed DAC
        StepAtten = (unsigned int)(fmin((int)(DesiredAtten/0.5), 63)*0.5);     // what step atten should be set to
        StepValue = (unsigned int)(StepAtten * 2.0);        // 6 bit drive setting to achieve that atten
        ResidualAtten = DesiredAtten - StepAtten;           // this needs to be achieved through the current setting drive
        DACDrive = (unsigned int)(255.0/pow(10.0,(ResidualAtten/20.0)));
        DACCurrentROM[Level] = DACDrive;
        DACStepAttenROM[Level] = StepAtten;
    }
}


//
// InitialiseCWKeyerRamp(void)
// calculates an "S" shape ramp curve and loads into RAM
// needs to be called before keyer enabled!
//
void InitialiseCWKeyerRamp(void)
{

}



//
// SetMOX(bool Mox)
// sets or clears TX state
// set or clear the relevant bit in GPIO
//
void SetMOX(bool Mox)
{
    uint32_t Register;

    Register = GPIORegValue;                    // get current settings
    if(Mox)
        Register |= (1<<VMOXBIT);
    else
        Register &= ~(1<<VMOXBIT);
    if(Register != GPIORegValue)                    // write back if different
    {
        GPIORegValue = Register;                    // store it back
//        RegisterWrite(VADDRRFGPIOREG, Register);  // and write to it
    }
}


//
// SetATUTune(bool TuneEnabled)
// drives the ATU tune output to selected state.
// set or clear the relevant bit in GPIO
//
void SetATUTune(bool TuneEnabled)
{
    uint32_t Register;

    Register = GPIORegValue;                    // get current settings
    if(TuneEnabled)
        Register |= (1<<VATUTUNEBIT);
    else
        Register &= ~(1<<VATUTUNEBIT);
    if(Register != GPIORegValue)                    // write back if different
    {
        GPIORegValue = Register;                    // store it back
//        RegisterWrite(VADDRRFGPIOREG, Register);  // and write to it
    }
}


//
// SetP1SampleRate(ESampleRate Rate)
// sets the sample rate for all DDC used in protocol 1. 
// allowed rates are 48KHz to 384KHz.
// save the new bits to stored values, and write to FPGA, for all DDC used in P1
//
void SetP1SampleRate(ESampleRate Rate)
{
    int Cntr;
    uint32_t ConfigReg;
    uint32_t RegisterValue;

    P1SampleRate = Rate;                                // rate for all DDC
    for(Cntr=0; Cntr < VNUMP1DDCS; Cntr++)
    {
        RegisterValue = DDCConfigReg[Cntr / 2];         // get current register setting
        if((Cntr & 1) == 0)                             // if even register
        {
            RegisterValue &= 0xFFFFFFE3;                // set sample rate to zero
            RegisterValue |= ((uint32_t)Rate) << 2;     // add in the new sample rate
        }
        else                                            // must be an odd register
        {
            RegisterValue &= 0xFFFFE3FF;                // set sample rate to zero
            RegisterValue |= ((uint32_t)Rate) << 10;    // add in the new sample rate
        }
        if(RegisterValue != DDCConfigReg[Cntr / 2])     // write back if changed
        {
            DDCConfigReg[Cntr / 2] = RegisterValue;         // write back
            ConfigReg = DDCConfigRegs[Cntr];                // get FPGA address
//            RegisterWrite(ConfigReg, RegisterValue);        // and write to it
        }
    }
}


//
// SetP2SampleRate(unsigned int DDC, unsigned int SampleRate)
// sets the sample rate for a single DDC (used in protocol 2)
// allowed rates are 48KHz to 1536KHz.
// simpler: just set one DDC config reg
//
void SetP2SampleRate(unsigned int DDC, unsigned int SampleRate)
{
    uint32_t ConfigReg;
    uint32_t RegisterValue;
    ESampleRate Rate = e48KHz;

    // look up enum value
    if(SampleRate == 96)
        Rate = e96KHz;
    else if(SampleRate == 192)
        Rate = e192KHz;
    else if(SampleRate == 384)
        Rate = e384KHz;
    else if(SampleRate == 768)
        Rate = e768KHz;
    else if(SampleRate == 1536)
        Rate = e1536KHz;

    RegisterValue = DDCConfigReg[DDC / 2];         // get current register setting
    if((DDC & 1) == 0)                              // if even register
    {
        RegisterValue &= 0xFFFFFF1C;                // set sample rate to zero
        RegisterValue |= ((uint32_t)Rate) << 2;     // add in the new sample rate
    }
    else                                            // must be an odd register
    {
        RegisterValue &= 0xFFFF1CFF;                // set sample rate to zero
        RegisterValue |= ((uint32_t)Rate) << 10;    // add in the new sample rate
    }
    if(RegisterValue != DDCConfigReg[DDC / 2])     //write back if changed
    {
        DDCConfigReg[DDC / 2] = RegisterValue;          // write back
        ConfigReg = DDCConfigRegs[DDC];                 // get FPGA address
//        RegisterWrite(ConfigReg, RegisterValue);        // and write to it
    }
}


//
// SetClassEPA(bool IsClassE)
// enables non linear PA mode
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

    Register = GPIORegValue;                        // get current settings
    BitMask = (0b1111111) << VOPENCOLLECTORBITS;
    Register = Register & ~BitMask;                 // strip old bits, add new
    Register |= (bits << VOPENCOLLECTORBITS);
    if(Register != GPIORegValue)                    // write back if changed
    {
        GPIORegValue = Register;                    // store it back
//        RegisterWrite(VADDRRFGPIOREG, Register);  // and write to it
    }
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
    Register = GPIORegValue;                        // get current settings
    Register &= ~(1 << RandBit);                    // strip old bits
    Register &= ~(1 << PGABit);
    Register &= ~(1 << DitherBit);

    if(PGA)                                         // add new bits where set
        Register |= (1 << PGABit);
    if(Dither)
        Register |= (1 << DitherBit);
    if(Random)
        Register |= (1 << RandBit);

    if(Register != GPIORegValue)                    // write back if changed
    {
        GPIORegValue = Register;                        // store it back
//        RegisterWrite(VADDRRFGPIOREG, Register);      // and write to it
    }
}



//
// SetDDCFrequency(unsigned int DDC, unsigned int Value, bool IsDeltaPhase)
// sets a DDC frequency.
// DDC: DDC number (0-9) of 0xFF to set RX test source frequency
// Value: 32 bit phase word or frequency word (1Hz resolution)
// IsDeltaPhase: true if a delta phase value, false if a frequency value (P1)
// calculate delta phase if required. Delta=2^32 * (F/Fs)
// store delta phase; write to FPGA register.
//
void SetDDCFrequency(unsigned int DDC, unsigned int Value, bool IsDeltaPhase)
{
    uint32_t DeltaPhase;                    // calculated deltaphase value
    uint32_t RegAddress;
    double fDeltaPhase;

    if(DDC >= VNUMDDC)                      // limit the DDC count to actual regs!
        DDC = VNUMDDC-1;
    if(!IsDeltaPhase)                       // ieif protocol 1
    {
        fDeltaPhase = (double)(2^32) * (double)Value / (double) VSAMPLERATE;
        DeltaPhase = (uint32_t)fDeltaPhase;
    }
    else
        DeltaPhase = (uint32_t)Value;

    if(DDCDeltaPhase[DDC] != DeltaPhase)    // write back if changed
    {
        DDCDeltaPhase[DDC] = DeltaPhase;        // store this delta phase
        RegAddress =DDCRegisters[DDC];          // get DDC reg address, 
//        RegisterWrite(VADDRTXDUCREG, DeltaPhase);  // and write to it
    }
}


//
// SetDUCFrequency(unsigned int DDC, unsigned int Value, bool IsDeltaPhase)
// sets a DUC frequency. (Currently only 1 DUC, therefore DUC must be 0)
// Value: 32 bit phase word or frequency word (1Hz resolution)
// IsDeltaPhase: true if a delta phase value, false if a frequency value (P1)
//
void SetDUCFrequency(unsigned int DUC, unsigned int Value, bool IsDeltaPhase)		// only accepts DUC=0 
{
    uint32_t DeltaPhase;                    // calculated deltaphase value
    double fDeltaPhase;

    if(!IsDeltaPhase)                       // ieif protocol 1
    {
        fDeltaPhase = (double)(2^32) * (double)Value / (double) VSAMPLERATE;
        DeltaPhase = (uint32_t)fDeltaPhase;
    }
    else
        DeltaPhase = (uint32_t)Value;

    if(DUCDeltaPhase != DeltaPhase)         // write back if changed
    {
        DUCDeltaPhase = DeltaPhase;             // store this delta phase
//        RegisterWrite(DUCDeltaPhase, DeltaPhase);  // and write to it
    }
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
}


//
// SetAlexRXOut(bool Enable)
// P1: sets the Alex RX output relay
// NOT USED by 7000 RF board
//
void SetAlexRXOut(bool Enable)
{
    GAlexRXOut = Enable;
}


//
// SetAlexTXAnt(unsigned int Bits)
// P1: set the Alex TX antenna bits.
// bits=00: ant1; 01: ant2; 10: ant3; other: chooses ant1
// set bits 10-8 in Alex TX reg
//
void SetAlexTXAnt(unsigned int Bits)
{
    uint32_t Register;                                  // modified register

    Register = GAlexTXRegister;                         // copy original register
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
    if(Register != GAlexTXRegister)                     // write back if changed
    {
        GAlexTXRegister = Register;
//        RegisterWrite(VADDRALEXSPIREG+VOFFSETALEXTXREG, Register);  // and write to it
    }
}


//
// SetAlexCoarseAttenuator(unsigned int Bits)
// P1: set the 0/10/20/30dB attenuator bits. NOT used for for 7000RF board.
// bits: 00=0dB, 01=10dB, 10=20dB, 11=30dB
// Simply store the data - NOT USED for this RF board
//
void SetAlexCoarseAttenuator(unsigned int Bits)
{
    GAlexCoarseAttenuatorBits = Bits;
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
}


//
// SetRX2GroundDuringTX(bool IsGrounded)
//
void SetRX2GroundDuringTX(bool IsGrounded)
{
    GRX2GroundDuringTX = IsGrounded;
}

//
// SetAlexTXFilters(unsigned int Bits)
// P1: set the Alex bits for TX LPF filter selection
// Bits follows the P1 protocol format. C0=0x12, byte C4 has TX
//
void SetAlexTXFilters(unsigned int Bits)
{
    uint32_t Register;                                          // modified register
    if(GAlexManualFilterSelect)
    {
        Register = GAlexTXRegister;                         // copy original register
        Register &= 0x1F0F;                                 // turn off all affected bits
        Register |= (Bits & 0x0F)<<4;                       // bits 3-0, moved up
        Register |= (Bits & 0x1C)<<9;                      // bits 6-4, moved up

        if(Register != GAlexTXRegister)                     // write back if changed
        {
            GAlexTXRegister = Register;
    //        RegisterWrite(VADDRALEXSPIREG+VOFFSETALEXTXREG, Register);  // and write to it
        }
    }
}


//
// EnableAlexManualFilterSelect(bool IsManual)
// used to select between automatic selection of filters, and remotely commanded settings.
// if Auto, the RX and TX filters are calculated when a frequency change occurs
//
void EnableAlexManualFilterSelect(bool IsManual)
{
    GAlexManualFilterSelect = IsManual;                 // just store the bit
}


//
// AlexManualRXFilters(unsigned int Bits, int RX)
// P2: provides a 16 bit word with all of the Alex settings for a single RX
// must be formatted according to the Alex specification
// RX=0 or 1: RX1; RX=2: RX2
//
void AlexManualRXFilters(unsigned int Bits, int RX)
{
    uint32_t Register;                                          // modified register
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
    //        RegisterWrite(VADDRALEXSPIREG+VOFFSETALEXRXREG, Register);  // and write to it
        }
    }
}


//
// DisableAlexTRRelay(bool IsDisabled)
// if parameter true, the TX RX relay is disabled and left in RX 
//
void DisableAlexTRRelay(bool IsDisabled)
{
    GEnableAlexTXRXRelay = !IsDisabled;                     // enable TXRX - opposite sense to stored bit
}


//
// AlexManualTXFilters(unsigned int Bits)
// P2: provides a 16 bit word with all of the Alex settings for TX
// must be formatted according to the Alex specification
//
void AlexManualTXFilters(unsigned int Bits)
{
    uint32_t Register;                                  // modified register
    if(GAlexManualFilterSelect)
    {
        Register = Bits;                         // new setting
        if(Register != GAlexTXRegister)                     // write back if changed
        {
            GAlexTXRegister = Register;
    //        RegisterWrite(VADDRALEXSPIREG+VOFFSETALEXTXREG, Register);  // and write to it
        }
    }
}


//
// SetApolloBits(bool EnableFilter, bool EnableATU, bool StartAutoTune)
// sets the control bits for Apollo. No support for these in Saturn at present.
//
void SetApolloBits(bool EnableFilter, bool EnableATU, bool StartAutoTune)
{
    GEnableApolloFilter = EnableFilter;
    GEnableApolloATU = EnableATU;
    GStartApolloAutoTune = StartAutoTune;
}


//
// SetApolloEnabled(bool EnableFilter)
// sets the enabled bit for Apollo. No support for these in Saturn at present.
//
void SetApolloEnabled(bool EnableFilter)
{
    GEnableApolloFilter = EnableFilter;
}



//
// SelectFilterBoard(bool IsApollo)
// Selects between Apollo and Alex controls. Currently ignored & hw supports only Alex.
//
void SelectFilterBoard(bool IsApollo)
{
    GIsApollo = IsApollo;
}


//
// EnablePPSStamp(bool Enabled)
// enables a "pulse per second" timestamp
//
void EnablePPSStamp(bool Enabled)
{
    GPPSEnabled = Enabled;
}


//
// SetTXDriveLevel(unsigned int Level)
// sets the TX DAC current via a PWM DAC output
// level: 0 to 255 drive level value (255 = max current)
// sets both step attenuator drive and PWM DAC drive for high speed DAC current,
// using ROMs calculated at initialise.
//
void SetTXDriveLevel(unsigned int Level)
{
    uint32_t RegisterValue = 0;
    uint32_t DACDrive, AttenDrive;

    Level &= 0xFF;                                  // make sure 8 bits only
    DACDrive = DACCurrentROM[Level];                // get PWM
    AttenDrive = DACStepAttenROM[Level];            // get step atten
    RegisterValue = DACDrive;                       // set drive level when RX
    RegisterValue |= (DACDrive << 8);               // set drive level when TX
    RegisterValue |= (AttenDrive << 16);            // set step atten when RX
    RegisterValue |= (AttenDrive << 24);            // set step atten when TX
    if(GTXDACCtrl != RegisterValue)                 // write back if changed
    {
        GTXDACCtrl = RegisterValue;
//            RegisterWrite(VADDRDACCTRLREG, RegisterValue);  // and write to it
    }
}


//
// SetMicBoost(bool EnableBoost)
// enables 20dB mic boost amplifier in the CODEC
// change bits in the codec register, and only write back if changed (I2C write is slow!)
//
void SetMicBoost(bool EnableBoost)
{
    unsigned int Register;

    Register = GCodecAnaloguePath;                      // get current setting

    Register &= 0xFFFE;                                 // remove old mic boost bit
    if(EnableBoost)
        Register |= 1;                                  // set new mic boost bit
    if(Register != GCodecAnaloguePath)                  // only write back if changed
    {
        GCodecAnaloguePath = Register;
//        CodecRegisterWrite(VCODECANALOGUEPATHREG, Register);
    }
}


//
// SetMicLineInput(bool IsLineIn)
// chooses between microphone and Line input to Codec
// change bits in the codec register, and only write back if changed (I2C write is slow!)
//
void SetMicLineInput(bool IsLineIn)
{
    unsigned int Register;

    Register = GCodecAnaloguePath;                      // get current setting

    Register &= 0xFFFB;                                 // remove old mic / line select bit
    if(!IsLineIn)
        Register |= 4;                                  // set new select bit
    if(Register != GCodecAnaloguePath)                  // only write back if changed
    {
        GCodecAnaloguePath = Register;
//        CodecRegisterWrite(VCODECANALOGUEPATHREG, Register);
    }
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
    Register = GPIORegValue;                        // get current settings
    Register &= ~(1 << VMICBIASENABLEBIT);          // strip old bits
    Register &= ~(1 << VMICPTTSELECTBIT);           // strip old bits
    Register &= ~(1 << VMICSIGNALSELECTBIT);
    Register &= ~(1 << VMICBIASSELECTBIT);

    if(!MicRing)                                      // add new bits where set
    {
        Register |= (1 << VMICSIGNALSELECTBIT);     // mic on tip
        Register |= (1 << VMICBIASSELECTBIT);       // and hence mic bias on tip
        Register &= ~(1 << VMICPTTSELECTBIT);       // PTT on ring
    }
    else
    {
        Register &= ~(1 << VMICSIGNALSELECTBIT);    // mic on ring
        Register &= ~(1 << VMICSIGNALSELECTBIT);    // bias on ring
        Register |= (1 << VMICPTTSELECTBIT);        // PTT on tip
    }
    if(EnableBias)
        Register |= (1 << VMICBIASENABLEBIT);
    GPTTEnabled = !EnablePTT;                       // used when PTT read back - just store opposite state

    if(GPIORegValue != Register)                    // write bsack if changed
    {
        GPIORegValue = Register;                        // store it back
//        RegisterWrite(VADDRRFGPIOREG, Register);      // and write to it
    }
}


//
// SetBalancedMicInput(bool Balanced)
// selects the balanced microphone input, not supported by current protocol code. 
// just set the bit into GPIO
//
void SetBalancedMicInput(bool Balanced)
{
    uint32_t Register;                              // FPGA register content
    Register = GPIORegValue;                        // get current settings
    Register &= ~(1 << VBALANCEDMICSELECT);         // strip old bit
    if(Balanced)
        Register |= (1 << VBALANCEDMICSELECT);      // set new bit
    
    if(GPIORegValue = Register)                     // write back if changed
    {
        GPIORegValue = Register;                        // store it back
//        RegisterWrite(VADDRRFGPIOREG, Register);      // and write to it
    }
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
//        CodecRegisterWrite(VCODECLLINEVOLREG, Register);
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
// SetADCAttenuator(EADCSelect ADC, unsigned int Atten, bool Enabled)
// sets the  stepped attenuator on the ADC input
// Atten provides a 5 bit atten value
// enabled: if false, zero attenuation is driven out
//
void SetADCAttenuator(EADCSelect ADC, unsigned int Atten, bool Enabled)
{
    uint32_t Register;                              // local copy
    Register = GRXADCCtrl;                          // get existing settings
    if(!Enabled)
        Atten=0;                                    // no atrenuation if not enabled
    if(ADC == eADC1)
    {
        Register &= 0xFFFFFFE0;                     // remove existing bits;
        Register |= (Atten & 0X1F);                 // add in new bits for ADC1
    }
    else
    {
        Register &= 0xFFFF83FF;                     // remove existing bits;
        Register |= (Atten & 0X1F) << 10;           // add in new bits for ADC2
    }
    if (Register != GRXADCCtrl)                     // only write back if changed
    {
        GRXADCCtrl = Register; 
//        RegisterWrite(VADDRADCCTRLREG, Register);      // and write to it
    }
}


//
// SetADCAttenDuringTX(unsigned int Atten1, unsigned int Atten2)
// sets the attenuation value to be set on the RX atten during TX.
//
void SetADCAttenDuringTX(unsigned int Atten1, unsigned int Atten2)
{
    uint32_t Register;                              // local copy
    Register = GRXADCCtrl;                          // get existing settings
    Register &= 0xFFF07C1F;                         // remove existing bits for ADC1&2;
    Register |= (Atten1 & 0X1F) << 5;               // add in new bits for ADC1
    Register |= (Atten2 & 0X1F) << 15;              // add in new bits for ADC2
    if (Register != GRXADCCtrl)                     // only write back if changed
    {
        GRXADCCtrl = Register; 
//        RegisterWrite(VADDRADCCTRLREG, Register);      // and write to it
    }
}

//
// SetCWKeyerReversed(bool Reversed)
// if set, swaps the paddle inputs
// not yet used, but will be
//
void SetCWKeyerReversed(bool Reversed)
{
    GCWKeysReversed = Reversed;                     // just save it for now
}


//
// SetCWKeyerSpeed(unsigned int Speed)
// sets the CW keyer speed, in WPM
// not yet used, but will be
//
void SetCWKeyerSpeed(unsigned int Speed)
{
    GCWKeyerSpeed = Speed;                          // just save it for now
}


//
// SetCWKeyerMode(unsigned int Mode)
// sets the CW keyer mode
// not yet used, but will be
//
void SetCWKeyerMode(unsigned int Mode)
{
    GCWKeyerMode = Mode;                            // just save it for now
}


//
// SetCWKeyerWeight(unsigned int Weight)
// sets the CW keyer weight value (7 bits)
// not yet used, but will be
//
void SetCWKeyerWeight(unsigned int Weight)
{
    GCWKeyerWeight = Weight;                        // just save it for now
}


//
// SetCWKeyerEnabled(bool Enabled)
// sets CW keyer spacing bit
//
void SetCWKeyerSpacing(bool Spacing)
{
    GCWKeyerSpacing = Spacing;
}


//
// SetCWKeyerEnabled(bool Enabled)
// enables or disables the CW keyer
// not yet used, but will be
//
void SetCWKeyerEnabled(bool Enabled)
{
    GCWKeyerEnabled = Enabled;
}


//
// SetCWKeyerBits(bool Enabled, bool Reversed, bool ModeB, bool Strict, bool BreakIn)
// set several bits associated with the CW iambic keyer
//
void SetCWKeyerBits(bool Enabled, bool Reversed, bool ModeB, bool Strict, bool BreakIn)
{
    GCWKeyerEnabled = Enabled;
    GCWKeysReversed = Reversed;                     // just save it for now
    GCWKeyerMode = ModeB;                            // just save it for now
    GCWKeyerSpacing = Strict;
    GCWKeyerBreakIn = BreakIn;
}




//
// SetDDCADC(int DDC, EADCSelect ADC)
// sets the ADC to be used for each DDC
// DDC = 0 to 9
//
void SetDDCADC(int DDC, EADCSelect ADC)
{
    uint32_t ConfigReg;
    uint32_t RegisterValue;
    uint32_t ADCSetting;

    ADCSetting = (uint32_t)ADC & 0x3;               // 2 bits with ADC setting
    RegisterValue = DDCConfigReg[DDC / 2];          // get current register setting
    if((DDC & 1) == 0)                              // if even register
    {
        RegisterValue &= 0xFFFFFFFC;                // set sample rate to zero
        RegisterValue |= ADCSetting;                // add in the new sample rate
    }
    else                                            // must be an odd register
    {
        RegisterValue &= 0xFFFFFCFF;                // set sample rate to zero
        RegisterValue |= ADCSetting << 8;           // add in the new sample rate
    }
    if(RegisterValue != DDCConfigReg[DDC / 2])      // write back if changed
    {
        DDCConfigReg[DDC / 2] = RegisterValue;          // write back
        ConfigReg = DDCConfigRegs[DDC];                 // get FPGA address
//        RegisterWrite(ConfigReg, RegisterValue);        // and write to it
    }
}


uint32_t GKeyerSidetoneVol;                             // sidetone volume for CW TX
uint32_t GCWKeyerSetup;                                 // keyer control register
#define VADDRKEYERCONFIGREG 0x40
#define VCWKEYERENABLE 31                               // enble bit
#define VCWKEYERHANG 8                                  // hang time is 17:8
#define VCWKEYERRAMP 18                                 // ramp time


//
// EnableCW (bool Enabled)
// enables or disables CW mode. If enabled, the key input engages TX automatically
// and generates sidetone.
//
void EnableCW (bool Enabled)
{
    uint32_t Register;

    Register = GCWKeyerSetup;                    // get current settings
    if(Enabled)
        Register |= (1<<VCWKEYERENABLE);
    else
        Register &= ~(1<<VCWKEYERENABLE);
    if(Register != GCWKeyerSetup)                    // write back if different
    {
        GCWKeyerSetup = Register;                    // store it back
//        RegisterWrite(VADDRKEYERCONFIGREG, Register);  // and write to it
    }
}


//
// SetCWSidetoneEnabled(bool Enabled)
// enables or disables sidetone. If disabled, the volume is set to zero in codec config reg
// only do something if the bit changes; note the volume setting function is relevant too
//
void SetCWSidetoneEnabled(bool Enabled)
{
    uint32_t Register;
    if(GSidetoneEnabled != Enabled)                     // only act if bit changed
    {
        Register = GCodecConfigReg;                     // get current settings
        Register &= 0x0000FFFF;                         // remove old volume bits
        if(Enabled)
            Register |= (GSidetoneVolume & 0xFF) << 8;  // add back new bits; resize to 16 bits
        GCodecConfigReg = Register;                     // store it back
//        RegisterWrite(VADDRCODECCONFIGREG, Register); // and write to it
    }
}


//
// SetCWSidetoneVol(unsigned int Volume)
// sets the sidetone volume level (7 bits, unsigned)
//
void SetCWSidetoneVol(unsigned int Volume)
{
    uint32_t Register;

    if(GSidetoneVolume != Volume)                       // only act if value changed
    {
        GSidetoneVolume = Volume;                       // set new value
        Register = GCodecConfigReg;                     // get current settings
        Register &= 0x0000FFFF;                         // remove old volume bits
        if(GSidetoneEnabled)
            Register |= (GSidetoneVolume & 0xFF) << 8;  // add back new bits; resize to 16 bits
        GCodecConfigReg = Register;                     // store it back
//        RegisterWrite(VADDRCODECCONFIGREG, Register);  // and write to it
    }
}


//
// SetCWPTTDelay(unsigned int Delay)
//  sets the delay (ms) before TX commences (8 bit delay value)
//
void SetCWPTTDelay(unsigned int Delay)
{
    uint32_t Register;

    Register = GCWKeyerSetup;                           // get current settings
    Register &= 0xFFFFFF00;                             // remove old bits
    Register |= (Delay &0xFF);                          // add back new bits
    if(Register != GCWKeyerSetup)                       // write back if different
    {
        GCWKeyerSetup = Register;                       // store it back
//        RegisterWrite(VADDRKEYERCONFIGREG, Register);  // and write to it
    }
}


//
// SetCWHangTime(unsigned int HangTime)
// sets the delay (ms) after CW key released before TX removed
// (10 bit hang time value)
//
void SetCWHangTime(unsigned int HangTime)
{
    uint32_t Register;

    Register = GCWKeyerSetup;                        // get current settings
    Register &= 0xFFFC00FF;                          // remove old bits
    Register |= (HangTime &0x3FF) << VCWKEYERHANG;   // add back new bits
    if(Register != GCWKeyerSetup)                    // write back if different
    {
        GCWKeyerSetup = Register;                    // store it back
//        RegisterWrite(VADDRKEYERCONFIGREG, Register);  // and write to it
    }
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
    uint32_t DeltaPhase;                            // DDS delta phase value
    double fDeltaPhase;                             // delta phase as a float

    fDeltaPhase = (double)(2^16) * (double)Frequency / (double) VCODECSAMPLERATE;
    DeltaPhase = ((uint32_t)fDeltaPhase) & 0xFFFF;

    Register = GCodecConfigReg;                     // get current settings
    Register &= 0x0000FFFF;                         // remove old bits
    Register |= DeltaPhase << 16;                   // add back new bits
    if(Register != GCodecConfigReg)                 // write back if different
    {
        GCodecConfigReg = Register;                 // store it back
//        RegisterWrite(VADDRCODECCONFIGREG, Register);  // and write to it
    }
}


//
// SetCWBreakInEnabled(bool Enabled)
// enables or disables full CW break-in
// I don't think this has any effect
//
void SetCWBreakInEnabled(bool Enabled)
{
    GCWBreakInEnabled = Enabled;
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
void SetXvtrEnable(bool Enabled)
{
    uint32_t Register;

    Register = GPIORegValue;                        // get current settings
    if(Enabled)
        Register |= (1<<VXVTRENABLEBIT);
    else
        Register &= ~(1<<VXVTRENABLEBIT);
    if(Register != GPIORegValue)                    // write back if different
    {
        GPIORegValue = Register;                    // store it back
//        RegisterWrite(VADDRRFGPIOREG, Register);  // and write to it
    }
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

    GPAEnabled = Enabled;                                   // just save for now
    Register = GPIORegValue;                    // get current settings
    if(!Enabled)
        Register |= (1<<VTXRELAYDISABLEBIT);
    else
        Register &= ~(1<<VTXRELAYDISABLEBIT);
    if(Register != GPIORegValue)                    // write back if different
    {
        GPIORegValue = Register;                    // store it back
//        RegisterWrite(VADDRRFGPIOREG, Register);  // and write to it
    }
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
// SetCWKeys(bool CWXMode, bool Dash, bool Dot)
// sets the CW key state from SDR application 
//
void SetCWKeys(bool CWXMode, bool Dash, bool Dot)
{
    GCWXMode = CWXMode;                                     // just save these 3 for now
    GDashPressed =Dash;
    GDotPressed = Dot;
}


//
// SetSpkrMute(bool IsMuted)
// enables or disables the Codec speaker output
//
void SetSpkrMute(bool IsMuted)
{
    uint32_t Register;

    GSpeakerMuted = IsMuted;                                // just save for now.
    Register = GPIORegValue;                    // get current settings
    if(IsMuted)
        Register |= (1<<VSPKRMUTEBIT);
    else
        Register &= ~(1<<VSPKRMUTEBIT);
    if(Register != GPIORegValue)                    // write back if different
    {
        GPIORegValue = Register;                    // store it back
//        RegisterWrite(VADDRRFGPIOREG, Register);  // and write to it
    }
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
// probably call every time an outgoig packet is put together initially
// but possibly do this one a timed basis.
//
void ReadStatusRegister(void)
{
    uint32_t StatusRegisterValue = 0;

//    StatusRegisterValue = RegisterRead(VADDRSTATUSREG);
    GStatusRegister = StatusRegisterValue;                        // save to global
}

//
// GetPTTInput(void)
// return true if PTT input is pressed.
// depends on the status register having been read before this is called!
//
bool GetPTTInput(void)
{
    bool Result = false;
    Result = (bool)(GStatusRegister & 1);                       // get PTT bit
    return Result;
}


//
// GetKeyerDashInput(void)
// return true if keyer dash input is pressed.
// depends on the status register having been read before this is called!
//
bool GetKeyerDashInput(void)
{
    bool Result = false;
    Result = (bool)((GStatusRegister >> VKEYINB) & 1);                       // get PTT bit

    return Result;
}



//
// GetKeyerDotInput(void)
// return true if keyer dot input is pressed.
// depends on the status register having been read before this is called!
//
bool GetKeyerDotInput(void)
{
    bool Result = false;
    Result = (bool)((GStatusRegister >> VKEYINA) & 1);                       // get PTT bit

    return Result;
}



//
// GetADCOverflow(void)
// return true if ADC amplitude overflow has occurred since last read.
// the overflow stored state is reset when this is read.
// returns bit0: 1 if ADC1 overflow; bit1: 1 if ARC2 overflow
//
unsigned int GetADCOverflow(void)
{
    unsigned int Result = 0;

//  Result = RegisterRead(VADDRADCOVERFLOWBASE);
    return (Result & 0x3);
}



//
// GetUserIOBits(void)
// return the user input bits
// returns IO4 in LSB, IO8 in bot 3
//
unsigned int GetUserIOBits(void)
{
    unsigned int Result = 0;
    Result = ((GStatusRegister >> VUSERIO4) & 0b1111);                       // get usder input 4/5/6/8

    return Result;
}



//
// unsigned int GetAnalogueIn(unsigned int AnalogueSelect)
// return one of 6 ADC values from the RF board analogue values
// the paramter selects which input is read. 
// AnalogueSelect=0: AIN1 .... AnalogueSepect=5: AIN6
unsigned int GetAnalogueIn(unsigned int AnalogueSelect)
{
    unsigned int Result = 0;
    AnalogueSelect &= 7;                                        // limit to 3 bits
//  Result = RegisterRead(VADDRALEXADCBASE + AnalogueSelect);
    return Result;
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
    GCodecLineGain = 0;                                     // Codec left line in gain register
    GCodecAnaloguePath = 0x14;                              // Codec analogue path register (mic input, no boost)
//    CodecRegisterWrite(VCODECRESETREG, 0x0);          // reset register: reset deveice
//    CodecRegisterWrite(VCODECACTIVATIONREG, 0x1);     // digital activation set to ACTIVE
//    CodecRegisterWrite(VCODECANALOGUEPATHREG, GCodecAnaloguePath);        // mic input, no boost
//    CodecRegisterWrite(VCODECPOWERDOWNREG, 0x0);      // all elements powered on
//    CodecRegisterWrite(VCODECDIGITALFORMATREG, 0x2);  // slave; no swap; right when LRC high; 16 bit, I2S
//    CodecRegisterWrite(VCODECSAMPLERATEREG, 0x0);     // no clock divide; rate ctrl=0; normal mode, oversample 256Fs
//    CodecRegisterWrite(VCODECDIGITALPATHREG, 0x0);    // no soft mute; no deemphasis; ADC high pss filter enabled
//    CodecRegisterWrite(VCODECLLINEVOLREG, GCodecLineGain);        // line in gain=0

}


//
// SetTXAmplitudeScaling (unsigned int Amplitude)
// sets the overall TX amplitude. This is normally set to a constant determined during development.
// 
void SetTXAmplitudeScaling (unsigned int Amplitude)
{
    uint32_t Register;

    GTXAmplScaleFactor = Amplitude;                             // save value
    Register = TXConfigRegValue;                                // get current settings
    Register &= 0xFFC0000F;                                     // remove old bits
    Register |= ((Amplitude & 0x3FFFF << VTXCONFIGSCALEBIT));   // add new bits
    if(Register != TXConfigRegValue)                            // write back if different
    {
        TXConfigRegValue = Register;                            // store it back
//        RegisterWrite(VADDRTXCONFIGREG, Register);              // and write to it
    }
}


//
// SetTXProtocol (bool Protocol)
// sets whether TX configured for P1 (48KHz) or P2 (192KHz)
//
void SetTXProtocol (bool Protocol)
{
    uint32_t Register;

    GTXProtocolP2 = Protocol;                           // save value
    Register = TXConfigRegValue;                        // get current settings
    Register &= 0xFFFFFF7;                              // remove old bit
    Register |= ((((unsigned int)Protocol)&1) << VTXCONFIGPROTOCOLBIT);            // add new bit
    if(Register != TXConfigRegValue)                    // write back if different
    {
        TXConfigRegValue = Register;                    // store it back
//        RegisterWrite(VADDRTXCONFIGREG, Register);  // and write to it
    }
}


//
// SetTXModulationTestSourceFrequency (unsigned int Freq)
// sets the TX modulation DDS source frequency. Only used for development.
// 
void SetTXModulationTestSourceFrequency (unsigned int Freq)
{
    uint32_t Register;

    Register = Freq;                        // get current settings
    if(Register != TXModulationTestReg)                    // write back if different
    {
        TXModulationTestReg = Register;                    // store it back
//        RegisterWrite(VADDRTXMODTESTREG, Register);  // and write to it
    }
}


//
// SetTXModulationSource(ETXModulationSource Source)
// selects the modulation source for the TX chain.
// this will need to be called operationally to change over between CW & I/Q
//
void SetTXModulationSource(ETXModulationSource Source)
{
    uint32_t Register;

    GTXModulationSource = Source;                       // save value
    Register = TXConfigRegValue;                        // get current settings
    Register &= 0xFFFFFFFC;                             // remove old bits
    Register |= ((unsigned int)Source);                 // add new bits
    if(Register != TXConfigRegValue)                    // write back if different
    {
        TXConfigRegValue = Register;                    // store it back
//        RegisterWrite(VADDRTXCONFIGREG, Register);  // and write to it
    }
}





//////////////////////////////////////////////////////////////////////////////////
// control the data transfer app
//


//
// SetDuplex(bool Enabled)
// if Enabled, the RX signal is transferred back during TX; else TX drive signal
//
void SetDuplex(bool Enabled)
{

}


//
// SetNumP1DDC(unsigned int Count)
// sets the number of DDCs for which data is transferred back to the PC in protocol 1
//
void SetNumP1DDC(unsigned int Count)
{

}


//
// SetDataEndian(unsigned int Bits)
// sets endianness for transferred data. See P2 specification, and not implemented yet.
//
void SetDataEndian(unsigned int Bits)
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



//
// SetDDCEnabled(unsigned int DDC, bool Enabled)
// set whether an DDC is enabled
// this may need to move!
//
void SetDDCEnabled(unsigned int DDC, bool Enabled)
{

}


//
// SetDDCInterleaved(unsigned int DDC, bool Interleaved)
// set whether an DDC is interleaved
//
void SetDDCInterleaved(unsigned int DDC, bool Interleaved)
{

}


//
// SetDDCSampleSize(unsigned int DDC, unsgned int Size)
// set sample resolution for DDC (only 24 bits supported)
//
void SetDDCSampleSize(unsigned int DDC, unsigned int Size)
{

}