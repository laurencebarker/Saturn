//////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 1 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// hwaccess.c:
// Hardware access to Saturn FPGA via PCI express
//
//////////////////////////////////////////////////////////////

#define _DEFAULT_SOURCE
#define _XOPEN_SOURCE 500

#ifdef __STDC_NO_ATOMICS__
#error This compiler does not support C11 atomics
#endif

#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>

#include <sys/mman.h>

#define VMEMBUFFERSIZE 32768										// memory buffer to reserve
#define AXIBaseAddress 0x10000									// address of StreamRead/Writer IP

#include "../common/hwaccess.h"


//
// mem read/write variables:
//
int register_fd;                             // device identifier


//
// open connection to the XDMA device driver for register and DMA access
//
int OpenXDMADriver(void) {
  int Result = 0;
  if ((register_fd = open("/dev/xdma0_user", O_RDWR)) == -1) {
    printf("register R/W address space not available\n");
  } else {
    printf("register access connected to /dev/xdma0_user\n");
    Result = 1;
  }
  return Result;
}




//
// initiate a DMA to the FPGA with specified parameters
// returns 1 if success, else 0
// fd: file device (an open file)
// SrcData: pointer to memory block to transfer
// Length: number of bytes to copy
// AXIAddr: offset address in the FPGA window 
//
int DMAWriteToFPGA(int fd, unsigned char* SrcData, uint32_t Length, uint32_t AXIAddr) {
  ssize_t rc; // response code

  rc = pwrite(fd, SrcData, Length, AXIAddr);
  if (rc < 0) {
    printf("pwrite 0x%x bytes to 0x%lx failed: %ld.\n", Length, (long) AXIAddr, rc);
    perror("DMA write");
    return -EIO;
  }
  return 0;
}


//
// initiate a DMA from the FPGA with specified parameters
// returns 1 if success, else 0
// fd: file device (an open file)
// DestData: pointer to memory block to transfer
// Length: number of bytes to copy
// AXIAddr: offset address in the FPGA window 
//
int DMAReadFromFPGA(int fd, unsigned char* DestData, uint32_t Length, uint32_t AXIAddr)
{
  ssize_t rc;

  rc = pread(fd, DestData, Length, AXIAddr);
  if (rc < 0) {
    printf("DMA read of 0x%x bytes from 0x%lx failed: %ld\n", Length, (long) AXIAddr, rc);
    perror("DMA read");
    return -EIO;
  }

  return 0;
}


//
// 32 bit register read over the AXILite bus
//
uint32_t RegisterRead(uint32_t Address) {
  uint32_t result = 0;

  ssize_t nread = pread(register_fd, &result, sizeof(result), (off_t) Address);
  if (nread != sizeof(result))
    printf("ERROR: register read: addr=0x%08X   error=%s\n", Address, strerror(errno));

  return result;
}

//
// 32 bit register write over the AXILite bus
//
void RegisterWrite(uint32_t Address, uint32_t Data) {
  ssize_t nsent = pwrite(register_fd, &Data, sizeof(Data), (off_t) Address);
  if (nsent != sizeof(Data))
    printf("ERROR: Write: addr=0x%08X   error=%s\n", Address, strerror(errno));
}
