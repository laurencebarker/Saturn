//////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 1 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// version.h:
// print version information from FPGA registers
//
//////////////////////////////////////////////////////////////

#ifndef __version_h
#define __version_h

#include <stdint.h>

#define VADDRUSERVERSIONREG 0x4004              // user defined version register
#define VADDRSWVERSIONREG 0XC000                // user defined s/w version register
#define VADDRPRODVERSIONREG 0XC004              // user defined product version register

//
// the identification scheme leaves open the possibility of other products with similar s/w & FPGA architecture
//
#define VMAXPRODUCTID 1							// product ID index limit
#define VMAXSWID 4								// software ID index limit

//
// define types for product responses
//
typedef enum 
{
    eInvalidProduct,                // productid = 1
    eSaturn                         // productid=Saturn
} EProductId;

typedef enum 
{
    ePrototype1,                // productid = 1
    eProductionV1                         // productid=Saturn
} EProductVersion;

typedef enum
{
    eInvalidSWID,
    e1stProtoFirmware,
    e2ndProtofirmware,
    eFallback,
    eFullFunction
} ESoftwareID;


//
// function call to get firmware ID and version
//
uint16_t GetFirmwareVersion(ESoftwareID* ID);

//
// prints version information from the registers
//
void PrintVersionInfo(void);

//
// Check for a fallback configuration
// returns true if FPGA is a fallback load
//
bool IsFallbackConfig(void);

#endif