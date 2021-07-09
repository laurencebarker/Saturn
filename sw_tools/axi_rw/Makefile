# change application name here (executable output name)
TARGET=axi_rw

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

GTKLIB=`pkg-config --cflags --libs gtk+-3.0`

# linker
LD=gcc
LDFLAGS=$(PTHREAD) $(GTKLIB) -rdynamic

OBJS=    $(TARGET).o

all: $(OBJS)
	$(LD) -o $(TARGET) $(OBJS) $(LDFLAGS)
    
%.o: %.c
	$(CC) -c -o $(@F) $(CFLAGS) $(GTKLIB) $<
    
clean:
	rm -f *.o $(TARGET) *.ui~


