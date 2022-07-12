# Makefile for spiadcread
# *****************************************************
# Variables to control Makefile operation
 
CC = gcc
CFLAGS = -Wall -Wextra -Wno-unused-function -g
TARGET = spiadcread
 
# ****************************************************
# Targets needed to bring the executable up to date
 
all: $(TARGET)

$(TARGET): spiadcread.o
	$(CC) $(CFLAGS) -o $(TARGET) spiadcread.o
 
 
spiadcread.o: spiadcread.c
	$(CC) $(CFLAGS) -c spiadcread.c

clean:
	rm -rf $(TARGET) *.o *.bin
