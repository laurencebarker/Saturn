# Makefile for spi-loader
# *****************************************************
# Variables to control Makefile operation
 
CC = g++
CFLAGS = -Wall -Wextra -Wno-unused-function -g
TARGET = load-FPGA
 
# ****************************************************
# Targets needed to bring the executable up to date
 
all: $(TARGET)

$(TARGET): Main.o xil_assert.o xil_io.o xspi.o xspi_options.o xspi_stats.o
	$(CC) $(CFLAGS) -o $(TARGET) Main.o xil_assert.o xil_io.o xspi.o xspi_options.o xspi_stats.o
 
 
Main.o: Main.cpp
	$(CC) $(CFLAGS) -c Main.cpp
 
xil_assert.o: xil_assert.c
	$(CC) $(CFLAGS) -c xil_assert.c
 
xil_io.o: xil_io.c
	$(CC) $(CFLAGS) -c xil_io.c
 
xspi.o: xspi.c
	$(CC) $(CFLAGS) -c xspi.c
 
xspi_options.o: xspi_options.c
	$(CC) $(CFLAGS) -c xspi_options.c

xspi_stats.o: xspi_stats.c
	$(CC) $(CFLAGS) -c xspi_stats.c

clean:
	rm -rf $(TARGET) *.o *.bin
