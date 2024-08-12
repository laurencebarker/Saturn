/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 1 
//
// copyright Laurence Barker November 2022
// licenced under GNU GPL3
//
// codecwrite.c:
// Hardware access to codec registers using SPI
//
////////////////////////////////////////////////////////////////


#define _DEFAULT_SOURCE
#define _XOPEN_SOURCE 500
#include "../common/hwaccess.h"
#include "../common/saturnregisters.h"
#include "stdio.h"
#include <pthread.h>

//
// mutexes to protect registers that are accessed from several threads
//
pthread_mutex_t CodecRegMutex;

//
// 8 bit Codec register write over the AXILite bus via SPI
// // using simple SPI writer IP
// given 7 bit register address and 9 bit data
//
void CodecRegisterWrite(uint32_t Address, uint32_t Data)
{
	uint32_t WriteData;

	WriteData = (Address << 9) | (Data & 0x01FFUL);
    pthread_mutex_lock(&CodecRegMutex);                       // get protected access
//	printf("writing data %04x to codec register %04x\n", Data, Address);
	  RegisterWrite(VADDRCODECSPIREG, WriteData); // and write to it
    pthread_mutex_unlock(&CodecRegMutex);                     // clear protected access
}

