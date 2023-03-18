//////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 1 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// auxadc.h:
// access on-chip voltage and temperature values

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
#include "../common/auxadc.h"
#include "../common/saturnregisters.h"
#include "../common/hwaccess.h"



#define VADDRXADCTEMPREG 0x18200              // die temperature register



//
// prints temperature information
// temperature conversion according to UG480 page 23
//
void PrintAuxADCInfo(void)
{
    uint32_t RegisterValue;
    float Temp;

    RegisterValue = RegisterRead(VADDRXADCTEMPREG);
    Temp = (float)RegisterValue * 503.975;
    Temp = Temp / 65536.0;
    Temp -= 273.15;

    printf("Die Temp = %4.1fC\n", Temp);
}




