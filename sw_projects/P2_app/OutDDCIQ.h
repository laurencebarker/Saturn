/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
// derived from Pavel Demin code 
//
// OutDDCIQ.h:
//
// header: handle "outgoing DDC I/Q data" message
//
//////////////////////////////////////////////////////////////

#ifndef __OutDDCIQ_h
#define __OutDDCIQ_h


#include <stdint.h>
#include "../common/saturntypes.h"
#include "../common/saturnregisters.h"

#define VDDCPACKETSIZE 1444             // each DDC I/Qpacket

typedef struct {
    int ddc_index;
    uint32_t sample_count;
} ActiveDDC;

typedef struct {
    ActiveDDC activeDDCs[VNUMDDC];
    int activeCount;
    uint32_t lastRateWord;
} DDCState;

//
// protocol 2 handler for outgoing DDC I/Q data Packet from SDR
//
void *OutgoingDDCIQ(void *arg);


//
// interface calls to get commands from PC settings
//


//
// HandlerCheckDDCSettings()
// called when DDC settings have been changed. Check which DDCs are enabled, and sample rate.
//
void HandlerCheckDDCSettings(void);

static void processDDCData(const uint8_t* readPtr, uint8_t** headPtr, const DDCState* state);

static void copyDDCData(const uint8_t* srcPtr, uint8_t* destPtr, uint32_t sampleCount);

static uint32_t AnalyseDDCHeaderAndUpdateActive(uint32_t RateWord, uint32_t* ddcCounts, DDCState* state);
#endif