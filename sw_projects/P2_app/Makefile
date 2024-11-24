# Makefile for p2app
# *****************************************************
# Variables to control Makefile operation
 
CC = gcc
LD = gcc
CFLAGS = -Wall -Wextra -Wno-unused-function -g -D_GNU_SOURCE
LDFLAGS = -lm -lpthread
LIBS = -lgpiod -li2c
TARGET = p2app
VPATH=.:../common
GIT_DATE := $(wordlist 2,5, $(shell git log -1 --format=%cd --date=rfc))
 
# ****************************************************
# Targets needed to bring the executable up to date

OBJS=    $(TARGET).o hwaccess.o saturnregisters.o codecwrite.o saturndrivers.o version.o generalpacket.o IncomingDDCSpecific.o  IncomingDUCSpecific.o InHighPriority.o InDUCIQ.o InSpkrAudio.o OutMicAudio.o OutDDCIQ.o OutHighPriority.o debugaids.o auxadc.o cathandler.o frontpanelhandler.o catmessages.o g2panel.o LDGATU.o g2v2panel.o i2cdriver.o andromedacatmessages.o Outwideband.o

all: $(OBJS)
	$(LD) -o $(TARGET) $(OBJS) $(LDFLAGS) $(LIBS)
 
 
%.o: %.c
	$(CC) -c -o $(@F) $(CFLAGS) -D GIT_DATE='"$(GIT_DATE)"' $<

clean:
	rm -rf $(TARGET) *.o *.bin
