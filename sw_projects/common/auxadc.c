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
#include <stdio.h>

#include "../common/auxadc.h"
#include "../common/hwaccess.h"






float GetDieTemperatureCelcius();

//
// prints temperature information
// temperature conversion according to UG480 page 23
//
void PrintAuxADCInfo(void)
{
  float Temp = GetDieTemperatureCelcius();

  printf("Die Temp = %4.1f°C\n", Temp);
}




