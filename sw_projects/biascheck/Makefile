# change application name here (executable output name)
TARGET=biascheck
VPATH=.:../common

# compiler
CC=gcc
# debug
DEBUG=-g
# optimisation
OPT=-O0
# warnings
WARN=-Wall

PTHREAD=-pthread

CCFLAGS=$(DEBUG) $(OPT) $(WARN) $(PTHREAD) -pipe

GTKLIB=`pkg-config --cflags --libs glib-2.0 gtk+-3.0`

# linker
LD=gcc
LDFLAGS=$(PTHREAD) $(GTKLIB) -rdynamic -lm

OBJS=    $(TARGET).o hwaccess.o saturnregisters.o codecwrite.o saturndrivers.o version.o debugaids.o

all: $(OBJS)
	$(LD) -o $(TARGET) $(OBJS) $(LDFLAGS)
    
%.o: %.c
	$(CC) -c -o $(@F) $(CFLAGS) $(GTKLIB) $<
    
clean:
	rm -f *.o $(TARGET) *.ui~


