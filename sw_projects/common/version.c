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
  FullVersionInfo info = GetFullVersionInfo();
  return (info.product.productId == SATURNPRODUCTID) &&
         (info.firmware.id == SATURNGOLDENCONFIGID);
}

//
// prints version information from the registers
//
void PrintVersionInfo(void)
{
  FullVersionInfo info = GetFullVersionInfo();

  printf("FPGA BIT file data code = %08x\n", info.dateCode);

  const char* prodString = (info.product.productId <= VMAXPRODUCTID) ?
                           ProductIDStrings[info.product.productId] : ProductIDStrings[0];

  const char* swString = (info.firmware.id <= VMAXSWID) ?
                         SWIDStrings[info.firmware.id] : SWIDStrings[0];

  printf(" Product: %s; Version = %d\n", prodString, info.product.productVersion);
  printf(" FPGA Firmware loaded: %s; FW Version = %d\n", swString, info.firmware.version >> 4);

  if (info.clockInfo == 0xF)
  {
    printf("All clocks present\n");
  }
  else
  {
    for (int i = 0; i < 4; i++)
    {
      if (info.clockInfo & (1 << i))
        printf("%s present\n", ClockStrings[i]);
      else
        printf("%s not present\n", ClockStrings[i]);
    }
  }
}


uint16_t GetFirmwareVersion(ESoftwareID* ID)
{
  FirmwareInfo info = GetFirmwareInfo();
  if (ID != NULL) {
    *ID = info.id;
  }
  return info.version;
}