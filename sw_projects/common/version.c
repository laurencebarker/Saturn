//////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 1 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// version.c:
// print version information from FPGA registers

//
//////////////////////////////////////////////////////////////

#define _DEFAULT_SOURCE
#define _XOPEN_SOURCE 500
#include <assert.h>
#include <fcntl.h>
#include <getopt.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>

#include <sys/types.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include "../common/saturntypes.h"
#include "../common/version.h"
#include "../common/saturnregisters.h"
#include "../common/hwaccess.h"



#define VADDRUSERVERSIONREG 0x4004              // user defined version register
#define VADDRSWVERSIONREG 0XC000                // user defined s/w version register
#define VADDRPRODVERSIONREG 0XC004              // user defined product version register


//
// the identification scheme leaves open the possibility of other products with similar s/w & FPGA architecture
//
#define VMAXPRODUCTID 1							// product ID index limit
#define VMAXSWID 4								// software ID index limit

char* ProductIDStrings[] =
{
	"invalid product ID",
	"Saturn"
};

//
// these are relevant to Saturn only!
//
char* SWIDStrings[] =
{
	"invalid software ID",
	"Saturn prototype, board test code",
	"Saturn prototype, with DSP",
	"Fallback Golden image",
	"Saturn, full function"
};

char* ClockStrings[] =
{
	"122.88MHz main clock",
	"10MHz Reference clock",
	"EMC config clock",
	"122.88MHz main clock"
};

#define SATURNPRODUCTID 1					// Saturn, any version
#define SATURNGOLDENCONFIGID 3				// "golden" configuration id



//
// Check for a fallback configuration
// returns true if FPGA is a fallback load
//
bool IsFallbackConfig(void)
{
	bool Result = false;
	uint32_t SoftwareInformation;			// swid & version
	uint32_t ProductInformation;			// product id & version
//	uint32_t DateCode;						// date code from user register in FPGA

//	uint32_t SWVer;							// s/w version
	uint32_t SWID;							// s/w id
//	uint32_t ProdVer;						// product version
	uint32_t ProdID;						// product id
//	uint32_t ClockInfo;						// clock status

	//
	// read the raw data from registers
	//
	SoftwareInformation = RegisterRead(VADDRSWVERSIONREG);
	ProductInformation = RegisterRead(VADDRPRODVERSIONREG);
//	DateCode = RegisterRead(VADDRUSERVERSIONREG);

//	ClockInfo = (SoftwareInformation & 0xF);				// 4 clock bits
//	SWVer = (SoftwareInformation >> 4) & 0xFFFF;			// 16 bit sw version
	SWID = SoftwareInformation >> 20;						// 12 bit software ID

//	ProdVer = ProductInformation & 0xFFFF;					// 16 bit product version
	ProdID = ProductInformation >> 16;						// 16 bit product ID

	if ((ProdID == SATURNPRODUCTID) && (SWID == SATURNGOLDENCONFIGID))
		Result = true;

	return Result;
}

//
// prints version information from the registers
//
void PrintVersionInfo(void)
{
	uint32_t SoftwareInformation;			// swid & version
	uint32_t ProductInformation;			// product id & version
	uint32_t DateCode;						// date code from user register in FPGA

	uint32_t SWVer, SWID;					// s/w version and id
	uint32_t ProdVer, ProdID;				// product version and id
	uint32_t ClockInfo;						// clock status
	uint32_t Cntr;
	uint32_t MajorVersion;

	char* ProdString;
	char* SWString;

	//
	// read the raw data from registers
	//
	SoftwareInformation = RegisterRead(VADDRSWVERSIONREG);
	ProductInformation = RegisterRead(VADDRPRODVERSIONREG);
	DateCode = RegisterRead(VADDRUSERVERSIONREG);
	printf("FPGA BIT file data code = %08x\n", DateCode);

	ClockInfo = (SoftwareInformation & 0xF);				// 4 clock bits
	SWVer = (SoftwareInformation >> 4) & 0xFFFF;			// 16 bit sw version
	SWID = (SoftwareInformation >> 20) & 0x1F;				// 5 bit software ID
	MajorVersion = SoftwareInformation >> 25;				// 7 bit major version

	ProdVer = ProductInformation & 0xFFFF;					// 16 bit product version
	ProdID = ProductInformation >> 16;						// 16 bit product ID

	//
	// now chack if IDs are valid and print strings
	//
	if (ProdID > VMAXPRODUCTID)
		ProdString = ProductIDStrings[0];
	else
		ProdString = ProductIDStrings[ProdID];

	if (SWID > VMAXSWID)
		SWString = SWIDStrings[0];
	else
		SWString = SWIDStrings[SWID];

	printf(" Product: %s; Version = %d\n", ProdString, ProdVer);
	printf(" FPGA Firmware loaded: %s; FW Version = %d, major version = %d\n", SWString, SWVer, MajorVersion);

	if (ClockInfo == 0xF)
		printf("All clocks present\n");
	else
	{
		for (Cntr = 0; Cntr < 4; Cntr++)
		{
			if (ClockInfo & 1)
				printf("%s present\n", ClockStrings[Cntr]);
			else
				printf("%s not present\n", ClockStrings[Cntr]);
			ClockInfo = ClockInfo >> 1;
		}
	}
}



//
// function call to get firmware ID and version
//
unsigned int GetFirmwareVersion(ESoftwareID* ID)
{
	unsigned int Version = 0;
	uint32_t SoftwareInformation;			// swid & version

	SoftwareInformation = RegisterRead(VADDRSWVERSIONREG);
	Version = (SoftwareInformation >> 4) & 0xFFFF;			// 16 bit sw version
	*ID = (ESoftwareID)((SoftwareInformation >> 20) & 0x1F);						// 5 bit software ID
	return Version;
}



//
// function call to get firmware major version
//
unsigned int GetFirmwareMajorVersion(void)
{
	unsigned int MajorVersion = 0;
	uint32_t SoftwareInformation;			// swid & version

	SoftwareInformation = RegisterRead(VADDRSWVERSIONREG);
	MajorVersion = (SoftwareInformation >> 25) & 0x7F;			// 7 bit major fw version
	return MajorVersion;
}