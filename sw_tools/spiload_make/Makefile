# Makefile for spi-loader
 
# *****************************************************
# Variables to control Makefile operation
 
CC = g++
CFLAGS = -Wall -Wextra -Wno-unused-function -g
 
# ****************************************************
# Targets needed to bring the executable up to date
 
main: main.o Point.o Square.o
    $(CC) $(CFLAGS) -o spiloader main.o xil_assert.o xil_io.o xspi.o xspi_options.o xspi_stats.o
 
# The main.o target can be written more simply
 
main.o: Main.cpp
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
	rm -rf spiloader *.o *.bin