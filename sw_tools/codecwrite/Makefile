# Makefile for codecwrite
# *****************************************************
# Variables to control Makefile operation
 
CC = gcc
CFLAGS = -Wall -Wextra -Wno-unused-function -g
TARGET = codecwrite
 
# ****************************************************
# Targets needed to bring the executable up to date
 
all: $(TARGET)

$(TARGET): codecwrite.o
	$(CC) $(CFLAGS) -o $(TARGET) codecwrite.o
 
 
codecwrite.o: codecwrite.c
	$(CC) $(CFLAGS) -c codecwrite.c

clean:
	rm -rf $(TARGET) *.o *.bin
