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
#define VNUMDDC 10                                  // downconverters available
#define VNUMP1DDCS 5                                // DDCs used for P1
#define VSAMPLERATE 122880000                       // sample rate in Hz

uint32_t DDCDeltaPhase[VNUMDDC];                    // DDC frequency settings
uint32_t DUCDeltaPhase;                             // DUC frequency setting
uint32_t GPIORegValue;                              // value stored into GPIO
bool GPTTEnabled;                                   // true if PTT is enabled
bool GPureSignalEnabled;                            // true if PureSignal is enabled
ESampleRate P1SampleRate;                           // rate for all DDC
ESampleRate P2DDCSampleRate[VNUMDDC];               // array for all DDCs
uint32_t DDCConfigReg[VNUMDDC/2];                   // config registers
bool GClassESetting;                                // NOT CURRENTLY USED - true if class E operation
bool GIsApollo;                                     // NOT CURRENTLY USED - true if Apollo filter selected
bool GPPSEnabled;                                   // NOT CURRENTLY USED - trie if PPS generation enabled
uint32_t GTXDACCtrl;                                // TX DAC current setting & atten


//
// local copies of Codec registers
//
unsigned int GCodecLineGain;                            // value written in Codec left line in gain register
unsigned int GCodecAnaloguePath;                        // value written in Codec analogue path register


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
#define VCODECLLINEVOLREG 0                             // left line input volume
#define VCODECRLINEVOLREG 1                             // right line input volume
#define VCODECLHEADPHONEVOLREG 2                        // left headphone volume
#define VCODECRHEADPHONEVOLREG 3                        // right headphone volume
#define VCODECANALOGUEPATHREG 4                         // analogue path control
#define VCODECDIGITALPATHREG 5                          // digital path control
#define VCODECPOWERDOWNREG 6                            // power down control
#define VCODECDIGITALFORMATREG 7                        // digital audio interface format register
#define VCODECSAMPLERATEREG 8                           // sample rate control
#define VCODECACTIVATIONREG 9                           // digital interface activation register
#define VCODECRESETREG 15                               // reset register


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

uint32_t DDCCONFIGREGS[VNUMDDC] = 
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
// bit addresses in status anf GPIO registers
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
#define VPTTIN2BIT 1
#define VKEYINA 2
#define VKEYINB 3
#define VUSERIO4 4
#define VUSERIO5 5
#define VUSERIO6 8
#define VUSERIO8 7
#define V13_8VDETECTBIT 8
#define VATUTUNECOMPLETEBIT 9
#define VEXTTXENABLEBIT 31



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
// SetMOX(bool Mox)
// sets or clears TX state
// set or clear the relevant bit in GPIO
//
void SetMOX(bool Mox)
{
    uint32_t Register;

    Register = GPIORegValue;                    // get current settings
    if(Mox)
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
// SetATUTune(bool TuneEnabled)
// drives the ATU tune output to selected state.
// set or clear the relevant bit in GPIO
//
void SetATUTune(bool TuneEnabled)
{
    uint32_t Register;

    Register = GPIORegValue;                    // get current settings
    if(TuneEnabled)
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
            RegisterValue &= 0xFFFFFF1C;                // set sample rate to zero
            RegisterValue |= ((uint32_t)Rate) << 2;     // add in the new sample rate
        }
        else                                            // must be an odd register
        {
            RegisterValue &= 0xFFFF1CFF;                // set sample rate to zero
            RegisterValue |= ((uint32_t)Rate) << 10;    // add in the new sample rate
        }
        if(RegisterValue != DDCConfigReg[Cntr / 2])     //write back if changed
        {
            DDCConfigReg[Cntr / 2] = RegisterValue;         // write back
            ConfigReg = DDCCONFIGREGS[Cntr];                // get FPGA address
//            RegisterWrite(ConfigReg, RegisterValue);        // and write to it
        }
    }
}


//
// SetP2SampleRate(unsigned int DDC, ESampleRate Rate)
// sets the sample rate for a single DDC (used in protocol 2)
// allowed rates are 48KHz to 1536KHz.
// simpler: just set one DDC config reg
//
void SetP2SampleRate(unsigned int DDC, ESampleRate Rate)
{
    uint32_t ConfigReg;
    uint32_t RegisterValue;
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
        ConfigReg = DDCCONFIGREGS[DDC];                 // get FPGA address
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

uint32_t GAlexTXRegister;                       // 16 bit used of 32 
uint32_t GAlexRXRegister;                       // 32 bit RX register
//////////////////////////////////////////////////////////////////////////////////

//	data to send to Alex Tx filters is in the following format:
//	Bit  0 - NC				U3 - D0
//	Bit  1 - NC				U3 - D1
//	Bit  2 - txrx_status    U3 - D2
//	Bit  3 - Yellow Led		U3 - D3
//	Bit  4 - 30/20m	LPF		U3 - D4
//	Bit  5 - 60/40m	LPF		U3 - D5
//	Bit  6 - 80m LPF		U3 - D6
//	Bit  7 - 160m LPF    	U3 - D7
//	Bit  8 - Ant #1			U5 - D0
//	Bit  9 - Ant #2			U5 - D1
//	Bit 10 - Ant #3			U5 - D2
//	Bit 11 - T/R relay		U5 - D3
//	Bit 12 - Red Led		U5 - D4
//	Bit 13 - 6m	LPF			U5 - D5
//	Bit 14 - 12/10m LPF		U5 - D6
//	Bit 15 - 17/15m	LPF		U5 - D7
// bit 4 (or bit 11 as sent by AXI) replaced by TX strobe

//	data to send to Alex Rx filters is in the folowing format:
//  bits 15:0 - RX1; bits 31:16 - RX1
// (IC designators and functions for 7000DLE RF board)
//	Bit  0 - Yellow LED 	  U6 - QA
//	Bit  1 - 10-22 MHz BPF 	  U6 - QB
//	Bit  2 - 22-35 MHz BPF 	  U6 - QC
//	Bit  3 - 6M Preamp    	  U6 - QD
//	Bit  4 - 6-10MHz BPF	  U6 - QE
//	Bit  5 - 2.5-6 MHz BPF 	  U6 - QF
//	Bit  6 - 1-2.5 MHz BPF 	  U6 - QG
//	Bit  7 - N/A      		  U6 - QH
//	Bit  8 - Transverter 	  U10 - QA
//	Bit  9 - Ext1 In      	  U10 - QB
//	Bit 10 - N/A         	  U10 - QC
//	Bit 11 - PS sample select U10 - QD
//	Bit 12 - RX1 Filt bypass  U10 - QE
//	Bit 13 - N/A 		      U10 - QF
//	Bit 14 - RX1 master in	  U10 - QG
//	Bit 15 - RED LED 	      U10 - QH
//	Bit 16 - Yellow LED 	  U7 - QA
//	Bit 17 - 10-22 MHz BPF 	  U7 - QB
//	Bit 18 - 22-35 MHz BPF 	  U7 - QC
//	Bit 19 - 6M Preamp    	  U7 - QD
//	Bit 20 - 6-10MHz BPF	  U7 - QE
//	Bit 21 - 2.5-6 MHz BPF 	  U7 - QF
//	Bit 22 - 1-2.5 MHz BPF 	  U7 - QG
//	Bit 23 - N/A      		  U7 - QH
//	Bit 24 - Transverter 	  U13 - QA
//	Bit 25 - Ext1 In      	  U13 - QB
//	Bit 26 - N/A         	  U13 - QC
//	Bit 27 - PS sample select U13 - QD
//	Bit 28 - RX1 Filt bypass  U13 - QE
//	Bit 29 - N/A 		      U13 - QF
//	Bit 30 - RX1 master in	  U13 - QG
//	Bit 31 - RED LED 	      U13 - QH



//
// SetAlexRXAnt(unsigned int Bits)
// P1: set the Alex RX antenna bits.
// bits=00: none; 01: RX1; 02: RX2; 03: transverter
//
void SetAlexRXAnt(unsigned int Bits)
{

}


//
// SetAlexRXOut(bool Enable)
// P1: sets the Alex RX output relay
//
void SetAlexRXOut(bool Enable)
{

}


//
// SetAlexTXAnt(unsigned int Bits)
// P1: set the Alex TX antenna bits.
// bits=00: ant1; 01: ant2; 10: ant3; other: chooses ant1
//
void SetAlexTXAnt(unsigned int Bits)
{

}


//
// EnableAlexManualFilterSelect(bool IsManual)
// used to select between automatic selection of filters, and remotely commanded settings.
// if Auto, the RX and TX filters are calculated when a frequency change occurs
//
void EnableAlexManualFilterSelect(bool IsManual)
{

}


//
// AlexManualRXFilters(unsigned int Bits, int RX)
// P2: provides a 16 bit word with all of the Alex settings for a single RX
// must be formatted according to the Alex specification
// RX=0 or 1: RX1; RX=2: RX2
//
void AlexManualRXFilters(unsigned int Bits, int RX)
{

}


//
// DisableAlexTRRelay(bool IsDisabled)
// if parameter true, the TX RX relay is disabled and left in RX 
//
void DisableAlexTRRelay(bool IsDisabled)
{

}


//
// AlexManualTXFilters(unsigned int Bits)
// P2: provides a 16 bit word with all of the Alex settings for TX
// must be formatted according to the Alex specification
//
void AlexManualTXFilters(unsigned int Bits)
{

}


//
// SetApolloBits(bool EnableFilter, bool EnableATU, bool StartAutoTune)
// sets the control bits for Apollo. No support for these in Saturn at present.
//
void SetApolloBits(bool EnableFilter, bool EnableATU, bool StartAutoTune)
{

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


unsigned int DACCurrentROM[256];                    // used for residual attenuation
unsigned int DACStepAttenROM[256];                  // provides most atten setting

//
// SetTXDriveLevel(unsigned int Dac, unsigned int Level)
// sets the TX DAC current via a PWM DAC output
// DAC: the DAC number (must be zero)
// level: 0 to 255 drive level value (255 = max current)
// sets both step attenuator drive and PWM DAC drive for high speed DAC current,
// using ROMs calculated at initialise.
//
void SetTXDriveLevel(unsigned int Dac, unsigned int Level)
{
    uint32_t RegisterValue = 0;
    uint32_t DACDrive, AttenDrive;

    if(Dac == 0)
    {
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
// SetOrionMicOptions(bool MicTip, bool EnableBias, bool EnablePTT)
// sets the microphone control inputs
// write the bits to GPIO. Note the register bits aren't directly the protocol input bits.
// note also that EnablePTT is actually a DISABLE signal (enabled = 0)
//
void SetOrionMicOptions(bool MicTip, bool EnableBias, bool EnablePTT)
{
    uint32_t Register;                              // FPGA register content
    Register = GPIORegValue;                        // get current settings
    Register &= ~(1 << VMICBIASENABLEBIT);          // strip old bits
    Register &= ~(1 << VMICPTTSELECTBIT);           // strip old bits
    Register &= ~(1 << VMICSIGNALSELECTBIT);
    Register &= ~(1 << VMICBIASSELECTBIT);

    if(MicTip)                                      // add new bits where set
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

}


//
// SetADCAttenDuringTX(unsigned int Atten)
// sets the attenuation value to be set on the RX atten during TX. Sets both ADCs.
//
void SetADCAttenDuringTX(unsigned int Atten)
{

}


//
// SetCWKeyerReversed(bool Reversed)
// if set, swaps the paddle inputs
//
void SetCWKeyerReversed(bool Reversed)
{

}


//
// SetCWKeyerSpeed(unsigned int Speed)
// sets the CW keyer speed, in WPM
//
void SetCWKeyerSpeed(unsigned int Speed)
{

}


//
// SetCWKeyerMode(unsigned int Mode)
// sets the CW keyer mode
//
void SetCWKeyerMode(unsigned int Mode)
{

}


//
// SetCWKeyerWeight(unsigned int Weight)
// sets the CW keyer weight value (7 bits)
//
void SetCWKeyerWeight(unsigned int Weight)
{

}


//
// SetCWKeyerEnabled(bool Enabled)
// enables or disables the CW keyer
//
void SetCWKeyerEnabled(bool Enabled)
{

}


//
// SetDDCADC(int DDC, EADCSelect ADC)
// sets the ADC to be used for each DDC
// DDC = 0 to 9
//
void SetDDCADC(int DDC, EADCSelect ADC)
{

}


//
// EnableCW (bool Enabled)
// enables or disables CW mode. If enabled, the key input engages TX automatically
// and generates sidetone.
//
void EnableCW (bool Enabled)
{

}


//
// SetCWSidetoneVol(unsigned int Volume)
// sets the sidetone volume level (7 bits, unsigned)
//
void SetCWSidetoneVol(unsigned int Volume)
{

}


//
// SetCWPTTDelay(unsigned int Delay)
//  sets the delay (ms) before TX commences
//
void SetCWPTTDelay(unsigned int Delay)
{

}


//
// SetCWHangTime(unsigned int HangTime)
// sets the delay (ms) after CW key released before TX removed
//
void SetCWHangTime(unsigned int HangTime)
{

}


//
// SetCWSidetoneFrequency(unsigned int Frequency)
// sets the CW audio sidetone frequency, in Hz
//
void SetCWSidetoneFrequency(unsigned int Frequency)
{

}


//
// SetCWSidetoneEnabled(bool Enabled)
// enables or disables sidetone. If disabled, the volume is set to zero
//
void SetCWSidetoneEnabled(bool Enabled)
{

}


//
// SetCWBreakInEnabled(bool Enabled)
// enables or disables full CW break-in
//
void SetCWBreakInEnabled(bool Enabled)
{

}


//
// SetMinPWMWidth(unsigned int Width)
// set class E min PWM width (not yet implemented)
//
void SetMinPWMWidth(unsigned int Width)
{

}


//
// SetMaxPWMWidth(unsigned int Width)
// set class E min PWM width (not yet implemented)
//
void SetMaxPWMWidth(unsigned int Width)
{

}


//
// SetXvtrEnable(bool Enabled)
// enables or disables transverter. If enabled, the PA is not keyed.
//
void SetXvtrEnable(bool Enabled)
{

}


//
// SetWidebandEnable(EADCSelect ADC)
// enables wideband sample collection from an ADC.
//
void SetWidebandEnable(EADCSelect ADC)
{

}


//
// SetWidebandSampleCount(unsigned int Samples)
// sets the wideband data collected count
//
void SetWidebandSampleCount(unsigned int Samples)
{

}


//
// SetWidebandSampleSize(unsigned int Bits)
// sets the sample size per packet used for wideband data transfers
//
void SetWidebandSampleSize(unsigned int Bits)
{

}


//
// SetWidebandUpdateRate(unsigned int Period_ms)
// sets the period (ms) between collections of wideband data
//
void SetWidebandUpdateRate(unsigned int Period_ms)
{

}


//
// SetWidebandPacketsPerFrame(unsigned int Count)
// sets the number of packets to be transferred per wideband data frame
//
void SetWidebandPacketsPerFrame(unsigned int Count)
{

}


//
// EnableTimeStamp(bool Enabled)
// enables a timestamp for RX packets
//
void EnableTimeStamp(bool Enabled)
{

}


//
// EnableVITA49(bool Enabled)
// enables VITA49 mode
//
void EnableVITA49(bool Enabled)
{

}


//
// SetAlexEnabled(unsigned int Alex)
// 8 bit parameter enables up to 8 Alex units.
//
void SetAlexEnabled(unsigned int Alex)
{

}


//
// SetPAEnabled(bool Enabled)
// true if PA is enabled. 
//
void SetPAEnabled(bool Enabled)
{

}


//
// SetTXDACCount(unsigned int Count)
// sets the number of TX DACs, Currently unused. 
//
void SetTXDACCount(unsigned int Count)
{

}


//
// SetDUCSampleRate(ESampleRate Rate)
// sets the DUC sample rate. 
// current Saturn h/w supports 48KHz for protocol 1 and 192KHz for protocol 2
//
void SetDUCSampleRate(ESampleRate Rate)
{

}


//
// SetDUCSampleSize(unsigned int Bits)
// sets the number of bits per sample.
// currently unimplemented, and protocol 2 always uses 24 bits per sample.
//
void SetDUCSampleSize(unsigned int Bits)
{

}


//
// SetDUCPhaseShift(unsigned int Value)
// sets a phase shift onto the TX output. Currently unimplemented. 
//
void SetDUCPhaseShift(unsigned int Value)
{

}


//
// SetCWKeys(bool CWXMode, bool Dash, bool Dot)
// sets the CW key state from SDR application 
//
void SetCWKeys(bool CWXMode, bool Dash, bool Dot)
{

}


//
// SetSpkrMute(bool IsMuted)
// enables or disables the Codec speaker output
//
void SetSpkrMute(bool IsMuted)
{

}


//
// SetUserOutputBits(unsigned int Bits)
// sets the user I/O bits
//
void SetUserOutputBits(unsigned int Bits)
{

}


/////////////////////////////////////////////////////////////////////////////////
// read settings from FPGA
//


//
// GetPTTInput(void)
// return true if PTT input is pressed.
//
bool GetPTTInput(void)
{
    bool Result = false;

    return Result;
}


//
// GetKeyerDashInput(void)
// return true if keyer dash input is pressed.
//
bool GetKeyerDashInput(void)
{
    bool Result = false;

    return Result;
}



//
// GetKeyerDotInput(void)
// return true if keyer dot input is pressed.
//
bool GetKeyerDotInput(void)
{
    bool Result = false;

    return Result;
}



//
// GetADCOverflow(unsigned int ADC)
// return true if ADC overflow has occurred since last read.
// the overflow stored state is reset when this is read.
//
bool GetADCOverflow(unsigned int ADC)
{
    bool Result = false;

    return Result;
}



//
// GetUserIOBits(void)
// return the user input bits
//
unsigned int GetUserIOBits(void)
{
    unsigned int Result = 0;

    return Result;
}



//
// unsigned int GetAnalogueIn(unsigned int AnalogueSelect)
// return one of 6 ADC values from the RF board analogue values
// the paramter selects which input is read. 
//
unsigned int GetAnalogueIn(unsigned int AnalogueSelect)
{
    unsigned int Result = 0;

    return Result;
}


//////////////////////////////////////////////////////////////////////////////////
// internal App register settings
// these are things not accessible from external SDR applications, including debug
//


//
// CodecInitialise(void)
// initialise the CODEC, with the register values that don't normally change
//
void CodecInitialise(void)
{

}


//
// SetTXAmplitudeScaling (unsigned int Amplitude)
// sets the overall TX amplitude. This is normally set to a constant determined during development.
//
void SetTXAmplitudeScaling (unsigned int Amplitude)
{

}


//
// SetTXModulationTestSourceFrequency (unsigned int Freq)
// sets the TX modulation DDS source frequency. Only used for development.
//
void SetTXModulationTestSourceFrequency (unsigned int Freq)
{

}


//
// SetTXModulationSource(ETXModulationSource Source)
// selects the modulation source for the TX chain.
// this will need to be called operationally to change over between CW & I/Q
//
void SetTXModulationSource(ETXModulationSource Source)
{

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



