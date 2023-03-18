# Makefile for p2app
# *****************************************************
# Variables to control Makefile operation
 
CC = gcc
LD = gcc
CFLAGS = -Wall -Wextra -Wno-unused-function -g -D_GNU_SOURCE
LDFLAGS = -lm -lpthread
TARGET = p2app
VPATH=.:../common
 
# ****************************************************
# Targets needed to bring the executable up to date

OBJS=    $(TARGET).o hwaccess.o saturnregisters.o codecwrite.o saturndrivers.o version.o generalpacket.o IncomingDDCSpecific.o  IncomingDUCSpecific.o InHighPriority.o InDUCIQ.o InSpkrAudio.o OutMicAudio.o OutDDCIQ.o OutHighPriority.o debugaids.o auxadc.o

all: $(OBJS)
	$(LD) -o $(TARGET) $(OBJS) $(LDFLAGS)
 
 
%.o: %.c
	$(CC) -c -o $(@F) $(CFLAGS) $<

clean:
	rm -rf $(TARGET) *.o *.bin
