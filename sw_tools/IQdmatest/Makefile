# Makefile for iqdmatest
# *****************************************************
# Variables to control Makefile operation
 
CC = gcc
CFLAGS = -Wall -Wextra -Wno-unused-function -g
TARGET = dmatest
 
# ****************************************************
# Targets needed to bring the executable up to date
 
all: $(TARGET)

$(TARGET): iqdmatest.o
	$(CC) $(CFLAGS) -o $(TARGET) iqdmatest.o
 
 
iqdmatest.o: iqdmatest.c
	$(CC) $(CFLAGS) -c iqdmatest.c

clean:
	rm -rf $(TARGET) *.o *.bin
