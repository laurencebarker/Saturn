/*
 * This file is part of the Xilinx DMA IP Core driver tools for Linux
 *
 * Copyright (c) 2016-present,  Xilinx, Inc.
 * All rights reserved.
 *
 * This source code is licensed under BSD-style license (found in the
 * LICENSE file in the root directory of this source tree)
 */
//
// modified LVB to use pread and pwrite

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <byteswap.h>
#include <string.h>
#include <errno.h>
#include <signal.h>
#include <fcntl.h>
#include <ctype.h>
#include <termios.h>

#include <sys/types.h>
#include <sys/mman.h>


#define FATAL do { fprintf(stderr, "Error at line %d, file %s (%d) [%s]\n", __LINE__, __FILE__, errno, strerror(errno)); exit(1); } while(0)

#define MAP_MASK (MAP_SIZE - 1)

int main(int argc, char **argv)
{
	int fd;
	void *map_base, *virt_addr;
	uint32_t read_result, writeval;
	off_t target;
	/* access width */
	int access_width = 'w';
	char *device;

	/* not enough arguments given? */
	if (argc < 2) {
		fprintf(stderr,
			"\nUsage:\t%s <device> <address> [[type] data]\n"
			"\tdevice  : character device to access\n"
			"\taddress : memory address to access\n"
			"\tdata    : data to be written for a write\n\n",
			argv[0]);
		exit(1);
	}

	printf("argc = %d\n", argc);

	device = strdup(argv[1]);
	printf("device: %s\n", device);
	target = strtoul(argv[2], 0, 0);
	printf("address: 0x%08x\n", (unsigned int)target);

	printf("access type: %s\n", argc > 3 ? "write" : "read");

	if ((fd = open(argv[1], O_RDWR)) == -1)
		FATAL;
	printf("character device %s opened.\n", argv[1]);
	fflush(stdout);


	/* read only */
	if (argc <= 3) 
	{
      ssize_t nread = pread(fd, &read_result, sizeof(read_result), (off_t) target);
      if (nread != sizeof(read_result))
      {
         printf("Error writing to device:%s", strerror(errno));
      }
		
		printf
		    ("Read 32-bit value at address 0x%08x : 0x%08x\n",
		     (unsigned int)target, (unsigned int)read_result);
		return (int)read_result;
		fflush(stdout);
	}
	/* data value given, i.e. writing? */
	if (argc >= 4) 
	{
		writeval = strtoul(argv[3], 0, 0);
		printf("Write 32-bits value 0x%08x to 0x%08x \n",
		       (unsigned int)writeval, (unsigned int)target);
      ssize_t nsent = pwrite(fd, &writeval, sizeof(writeval), (off_t) target); 
      if (nsent != sizeof(writeval))
      {
         printf("Error writing to device:%s", strerror(errno));
      }

		fflush(stdout);
	}
	close(fd);
	return 0;
}
