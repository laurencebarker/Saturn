# change application name here (executable output name)
TARGET=flashwriter
VPATH=.:../../sw_projects/common


# compiler
CC=g++
# debug
DEBUG=-g
# optimisation
OPT=-O0
# warnings
WARN=-Wall

PTHREAD=-pthread

CCFLAGS=$(DEBUG) $(OPT) $(WARN) $(PTHREAD) -pipe

GTKLIB=`pkg-config --cflags --libs gtk+-3.0`

# linker
LD=g++
LDFLAGS=$(PTHREAD) $(GTKLIB) -rdynamic

OBJS=    $(TARGET).o spi-s25fl.o xil_assert.o xil_io.o xspi.o xspi_options.o xspi_stats.o hwaccess.o version.o

all: $(OBJS)
	$(LD) -o $(TARGET) $(OBJS) $(LDFLAGS)
    
%.o: %.c
	$(CC) -c -o $(@F) $(CFLAGS) $(GTKLIB) $<

%.o: %.cpp
	$(CC) -c -o $(@F) $(CFLAGS) $(GTKLIB) $<
    
clean:
	rm -f *.o $(TARGET) *.ui~


