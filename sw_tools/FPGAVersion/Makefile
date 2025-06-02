# Makefile for FPGAVersion
# *****************************************************
# Variables to control Makefile operation
 
CC = gcc
LD = gcc
CFLAGS = -Wall -Wextra -Wno-unused-function -g -D_GNU_SOURCE
LDFLAGS = -lm -lpthread
TARGET = FPGAVersion
VPATH=.:../../sw_projects/common
 
# ****************************************************
# Targets needed to bring the executable up to date

OBJS=    $(TARGET).o hwaccess.o version.o

all: $(OBJS)
	$(LD) -o $(TARGET) $(OBJS) $(LDFLAGS)
 
 
%.o: %.c
	$(CC) -c -o $(@F) $(CFLAGS) $<

clean:
	rm -rf $(TARGET) *.o *.bin
