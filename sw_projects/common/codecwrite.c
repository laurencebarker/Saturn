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
#include <semaphore.h>
#include <unistd.h>

//
// semaphores to protect registers that are accessed from several threads
//
sem_t CodecRegMutex;

//
// 8 bit Codec register write over the AXILite bus via SPI
// using simple SPI writer IP
// given 7 bit register address and 8 bit data
// (the 9th, top data bit is always 0 for a write so only 8 useful bits)
//
void CodecRegisterWrite(uint32_t Address, uint32_t Data)
{
	uint32_t WriteData;

	WriteData = (Address << 9) | (Data & 0x01FFUL);
    sem_wait(&CodecRegMutex);                       // get protected access
//	printf("writing data %04x to codec register %04x\n", Data, Address);
	RegisterWrite(VADDRCODECSPIREG, WriteData);  	// and write to it
    usleep(5);
    sem_post(&CodecRegMutex);                       // clear protected access
	printf("writing codec register 0x%x with data 0x%x\n",Address, Data);
}


//
// 8 bit Codec register read over the AXILite bus via SPI
// using simple SPI writer IP
// given 7 bit register address
// note this function will work with the IP we've had for a while;
// but only transfers data using the new TLV320AIC3204 codec)
//
uint8_t CodecRegisterRead(uint32_t Address)
{
	uint32_t WriteData;
	uint32_t ReadData;

	WriteData = (Address << 9) | (1<<8);			// shift out address and 1 bit
    sem_wait(&CodecRegMutex);                       // get protected access
//	printf("reading using shifted data %04x to codec register %04x\n", Data, Address);
	RegisterWrite(VADDRCODECSPIREG, WriteData);  	// and write to it
	usleep(10);										// small wait for that shift to complete
	ReadData = RegisterRead(VADDRCODECSPIREADREG);
    usleep(5);
    sem_post(&CodecRegMutex);                       // clear protected access
	printf("reading codec register 0x%x: read back data= 0x%x\n",Address, ReadData);

	return (uint8_t) (ReadData & 0xFF);
}
