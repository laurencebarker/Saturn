# Makefile for dmatest
# *****************************************************
# Variables to control Makefile operation
 
CC = gcc
CFLAGS = -Wall -Wextra -Wno-unused-function -g
TARGET = dmatest
 
# ****************************************************
# Targets needed to bring the executable up to date
 
all: $(TARGET)

$(TARGET): dmatest.o
	$(CC) $(CFLAGS) -o $(TARGET) dmatest.o
 
 
dmatest.o: dmatest.c
	$(CC) $(CFLAGS) -c dmatest.c

clean:
	rm -rf $(TARGET) *.o *.bin
