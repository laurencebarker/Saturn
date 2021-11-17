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


//
// local copies of values written to registers
//
#define VNUMDDC 10                                  // downconverters available
#define VSAMPLERATE 122880000                       // sample rate in Hz
uint32_t DDCDeltaPhase[VNUMDDC];
uint32_t DUCDeltaPhase;
uint32_t GPIORegValue;                              // value stored into GPIO
bool GPTTEnabled;                                   // true if PTT is enabled
bool GPureSignalEnabled;                            // true if PureSignal is enabled


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
    GPIORegValue = Register;                    // store it back
//    RegisterWrite(VADDRRFGPIOREG, Register);  // and write to it
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
    GPIORegValue = Register;                    // store it back
//    RegisterWrite(VADDRRFGPIOREG, Register);  // and write to it
}

//
// SetP1SampleRate(ESampleRate Rate)
// sets the sample rate for all DDC used in protocol 1. 
// allowed rates are 48KHz to 384KHz.
//
void SetP1SampleRate(ESampleRate Rate)
{

}


//
// SetP2SampleRate(unsigned int DDC, ESampleRate Rate)
// sets the sample rate for a single DDC (used in protocol 2)
// allowed rates are 48KHz to 1536KHz.
//
void SetP2SampleRate(unsigned int DDC, ESampleRate Rate)
{

}


//
// SetClassEPA(bool IsClassE)
// enables non linear PA mode
// This is not usded in the current Saturn design
//
void SetClassEPA(bool IsClassE)
{

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
    GPIORegValue = Register;                    // store it back
//    RegisterWrite(VADDRRFGPIOREG, Register);  // and write to it
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
    GPIORegValue = Register;                        // store it back
//    RegisterWrite(VADDRRFGPIOREG, Register);      // and write to it
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

    DDCDeltaPhase[DDC] = DeltaPhase;        // store this delta phase
    RegAddress =DDCRegisters[DDC];          // get DDC reg address, 
//    RegisterWrite(VADDRTXDUCREG, DeltaPhase);  // and write to it
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

    DUCDeltaPhase = DeltaPhase;             // store this delta phase
//    RegisterWrite(DUCDeltaPhase, DeltaPhase);  // and write to it
}


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
    
}


//
// EnablePPSStamp(bool Enabled)
// enables a "pulse per second" timestamp
//
void EnablePPSStamp(bool Enabled)
{

}


//
// SetTXDriveLevel(unsigned int Dac, unsigned int Level)
// sets the TX DAC current via a PWM DAC output
// DAC: the DAC number (must be zero)
// level: 0 to 255 drive level value (255 = max current)
//
void SetTXDriveLevel(unsigned int Dac, unsigned int Level)
{

}


//
// SetMicBoost(bool EnableBoost)
//  enables 20dB mic boost amplifier in the CODEC
//
void SetMicBoost(bool EnableBoost)
{

}


//
// SetMicLineInput(bool IsLineIn)
// chooses between microphone and Line input to Codec
//
void SetMicLineInput(bool IsLineIn)
{

}


#define VMICBIASENABLEBIT 0
#define VMICPTTSELECTBIT 1
#define VMICSIGNALSELECTBIT 2
#define VMICBIASSELECTBIT 3

//
// SetOrionMicOptions(bool MicTip, bool EnableBias, bool EnablePTT)
// sets the microphone control inputs
// write the bits to GPIO. Note the register bits aren't directly the protocol input bits!
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
    GPTTEnabled = EnablePTT;                        // used when PTT read back - just store state

    GPIORegValue = Register;                        // store it back
//    RegisterWrite(VADDRRFGPIOREG, Register);      // and write to it
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
        Register |= (1 << VBALANCEDMICSELECT);          // set new bit
    GPIORegValue = Register;                        // store it back
//    RegisterWrite(VADDRRFGPIOREG, Register);      // and write to it
}


//
// SetCodecLineInGain(unsigned int Gain)
// sets the line input level register in the Codec (4 bits)
//
void SetCodecLineInGain(unsigned int Gain)
{

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



