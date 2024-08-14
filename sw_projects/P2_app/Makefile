# Makefile for p2app
# *****************************************************
# Variables to control Makefile operation
#
# -march and -mcpu flags are added so the compiler optimizes for the Raspberry Pi CM4
# running a 64-bit OS, but should be removed if developing on a different platform.

CC = gcc
LD = gcc
CFLAGS = -Wall -Wextra -Wno-unused-function -g -D_GNU_SOURCE -flto -O2 -march=armv8-a+crc -mcpu=cortex-a72
LDFLAGS = -lm -lpthread -flto
LIBS = -lgpiod -li2c
TARGET = p2app
VPATH=.:../common
GIT_DATE := $(wordlist 2,5, $(shell git log -1 --format=%cd --date=rfc))
 
# ****************************************************
# Targets needed to bring the executable up to date

OBJS=    $(TARGET).o hwaccess.o saturnregisters.o saturndrivers.o version.o generalpacket.o IncomingDDCSpecific.o  IncomingDUCSpecific.o InHighPriority.o InDUCIQ.o InSpkrAudio.o OutMicAudio.o OutDDCIQ.o OutHighPriority.o auxadc.o cathandler.o frontpanelhandler.o catmessages.o g2panel.o LDGATU.o g2v2panel.o i2cdriver.o andromedacatmessages.o

all: $(OBJS)
	$(LD) -o $(TARGET) $(OBJS) $(LDFLAGS) $(LIBS)
 
 
%.o: %.c
	$(CC) -c -o $(@F) $(CFLAGS) -D GIT_DATE='"$(GIT_DATE)"' $<

clean:
	rm -rf $(TARGET) *.o *.bin
