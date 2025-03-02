/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// FPGAVersion.c:
//
// display FPGA version
//
//////////////////////////////////////////////////////////////


#include <stdio.h>
#include <errno.h>
#include <stdlib.h>
#include <limits.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <math.h>
#include <sys/types.h>


#include "../../sw_projects/common/hwaccess.h"                     // access to PCIe read & write
//#include "../../sw_projects/common/saturnregisters.h"              // register I/O for Saturn
#include "../../sw_projects/common/version.h"                      // version I/O for Saturn

//------------------------------------------------------------------------------------------
// VERSION History
// V1, 1/3/2025:   initial release






//
// main program. Ijust get version information and display
//
int main()
{
  int FWVersion;
  ESoftwareID FWID;

  OpenXDMADriver(true);
  FWVersion = GetFirmwareVersion(&FWID);
  printf("FPGA Firmware version = %d\n", FWVersion);
}


