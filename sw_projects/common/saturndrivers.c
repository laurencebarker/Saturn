/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 1 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// saturndrivers.c:
// Drivers for minor IP cores
//
//////////////////////////////////////////////////////////////


#include "../common/saturndrivers.h"
#include "../common/hwaccess.h"                   // low level access
#include <pthread.h>
#include <string.h>

pthread_mutex_t DDCResetFIFOMutex;

bool GFIFOSizesInitialised = false;




//
// void SetupFIFOMonitorChannel(EDMAStreamSelect Channel, bool EnableInterrupt);
//
// Setup a single FIFO monitor channel.
//   Channel:			IP channel number (enum)
//   EnableInterrupt:	true if interrupt generation enabled for overflows
// modified 28/9/2023 to remove "write FIFO": FPGA now detects overflow AND underflow
//
void SetupFIFOMonitorChannel(EDMAStreamSelect Channel, bool EnableInterrupt)
{
  if (!GFIFOSizesInitialised)
	{
			InitialiseFIFOSizes();				// load FIFO size table, if not already done
			GFIFOSizesInitialised = true;
	}
  WriteFIFOConfigRegister(&Channel, EnableInterrupt);
}




// Read number of locations in a FIFO
// for a read FIFO: returns the number of occupied locations available to read
// for a write FIFO: returns the number of free locations available to write
//   Channel:			IP core channel number (enum)
//   Overflowed:		true if an overflow has occurred. Reading clears the overflow bit.
//   OverThreshold:		true if overflow occurred  measures by threshold. Cleared by read.
//   Underflowed:       true if underflow has occurred. Cleared by read.
//   Current:           number of locations occupied (in either FIFO type)
//
uint32_t ReadFIFOMonitorChannel(EDMAStreamSelect Channel, bool* Overflowed, bool* OverThreshold, bool* Underflowed, uint16_t* Current)
{
  uint32_t status = ReadChannelStatusRegister(Channel);

  *Overflowed = (status >> 31) & 1;
  *OverThreshold = (status >> 30) & 1;
  *Underflowed = (status >> 29) & 1;

  uint16_t count = status & 0xFFFF; // strip to 16 bits

  // Use memcpy for safe, aligned write
  memcpy(Current, &count, sizeof(uint16_t));

  if (Channel == eTXDUCDMA || Channel == eSpkCodecDMA) {
    return DMAFIFODepths[Channel] - count;  // Free locations for write channels
  }

  return count;  // Occupied locations for read channels (16 bit FIFO count)
}


//
// reset a stream FIFO
//
void ResetDMAStreamFIFO(EDMAStreamSelect DDCNum)
{
	uint32_t Data;										// DDC register content
	uint32_t DataBit;

	switch (DDCNum)
	{
		case eRXDDCDMA:							// selects RX
			DataBit = (1 << VBITDDCFIFORESET);
			break;

		case eTXDUCDMA:							// selects TX
			DataBit = (1 << VBITDUCFIFORESET);
			break;

		case eMicCodecDMA:						// selects mic samples
			DataBit = (1 << VBITCODECMICFIFORESET);
			break;

		case eSpkCodecDMA:						// selects speaker samples
			DataBit = (1 << VBITCODECSPKFIFORESET);
			break;
	}

  pthread_mutex_lock(&DDCResetFIFOMutex);             // get protected access
	Data = RegisterRead(VADDRFIFORESET);				// read current content
	Data = Data & ~DataBit;
	RegisterWrite(VADDRFIFORESET, Data);				// set reset bit to zero
	Data = Data | DataBit;
	RegisterWrite(VADDRFIFORESET, Data);				// set reset bit to 1
	pthread_mutex_unlock(&DDCResetFIFOMutex);           // release protected access
}



//
// SetTXAmplitudeEER (bool EEREnabled)
// enables amplitude restoratino mode. Generates envelope output alongside I/Q samples.
// NOTE hardware does not properly support this yet!
// 
void SetTXAmplitudeEER(bool EEREnabled)
{
	GEEREnabled = EEREnabled;								// save value
	HandlerSetEERMode(EEREnabled);							// I/Q send handler
}


//
// number of samples to read for each DDC setting
// these settings must match behaviour of the FPGA IP!
// a value of "7" indicates an interleaved DDC
// and the rate value is stored for *next* DDC
//
static const uint32_t DDCSampleCounts[] =
{
	0,					// set to zero so no samples transferred
	1,
	2,
	4,
	8,
	16,
	32,
	0						// when set to 7, use next value & double it
};


//
// uint32_t AnalyseDDCHeader(unit32_t Header, unit32_t** DDCCounts)
// parameters are the header read from the DDC stream, and
// a pointer to an array [DDC count] of ints
// the array of ints is populated with the number of samples to read for each DDC
// returns the number of words per frame, which helps set the DMA transfer size
//
inline uint32_t AnalyseDDCHeader(uint32_t header, uint32_t* restrict ddc_counts) {
  uint32_t total = 0;

  for (int ddc = 0; ddc < VNUMDDC; ddc++) {
    uint32_t rate = header & 0x7;
    uint32_t count;

    if (rate != 7) {
      count = DDCSampleCounts[rate];
      ddc_counts[ddc] = count;
    } else {
      // interleaved
      header >>= 3;
      rate = header & 0x7;
      count = 2 * DDCSampleCounts[rate];
      ddc_counts[ddc] = count;

      if (ddc + 1 < VNUMDDC) { // this prevents a bug from triggering - don't access beyond length of array VNUMDDC
        ddc_counts[ddc + 1] = 0;
        ddc++;
      }
    }

    total += count;
    header >>= 3;
  }

  return total;
}
