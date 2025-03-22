//////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 1 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// hwaccess.h:
// Hardware access to Saturn FPGA via PCI express
//
//////////////////////////////////////////////////////////////

#ifndef __hwaccess_h
#define __hwaccess_h

#include <stdint.h>
#include <stdbool.h>


//
// open connection to the XDMA device driver for register and DMA access
//
int OpenXDMADriver(bool Silent);

//
// close connection
//
void CloseXDMADriver(void);


//
// initiate a DMA to the FPGA with specified parameters
// returns 1 if success, else 0
// fd: file device (an open file)
// SrcData: pointer to memory block to transfer
// Length: number of bytes to copy
// AXIAddr: offset address in the FPGA window 
//
int DMAWriteToFPGA(int fd, unsigned char*SrcData, uint32_t Length, uint32_t AXIAddr);



//
// initiate a DMA from the FPGA with specified parameters
// returns 1 if success, else 0
// fd: file device (an open file)
// DestData: pointer to memory block to transfer
// Length: number of bytes to copy
// AXIAddr: offset address in the FPGA window 
//
int DMAReadFromFPGA(int fd, unsigned char*DestData, uint32_t Length, uint32_t AXIAddr);


//
// single 32 bit register read, from AXI-Lite bus
//
uint32_t RegisterRead(uint32_t Address);


//
// single 32 bit register write, to AXI-Lite bus
//
void RegisterWrite(uint32_t Address, uint32_t Data);


#endif
