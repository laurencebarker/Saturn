# Makefile for p2app
# *****************************************************
# Variables to control Makefile operation

CC = gcc
LD = gcc
CFLAGS = -Wall -Wextra -Wno-unused-function -g -D_GNU_SOURCE
LDFLAGS = -lm -lpthread
LIBS = -li2c
TARGET = p2app
VPATH=.:../common
GIT_DATE := $(wordlist 2,5, $(shell git log -1 --format=%cd --date=rfc))

SRCS = $(TARGET).c hwaccess.c saturnregisters.c codecwrite.c saturndrivers.c version.c generalpacket.c IncomingDDCSpecific.c  IncomingDUCSpecific.c InHighPriority.c InDUCIQ.c InSpkrAudio.c OutMicAudio.c OutDDCIQ.c OutHighPriority.c debugaids.c auxadc.c cathandler.c frontpanelhandler.c catmessages.c g2panel.c LDGATU.c g2v2panel.c i2cdriver.c andromedacatmessages.c Outwideband.c serialport.c AriesATU.c
OBJS = $(SRCS:.c=.o)

# for cppcheck
CPP_OPTIONS= --inline-suppr --enable=all --suppress=unmatchedSuppression
CPP_OPTIONS += -D__linux__ --suppress=missingIncludeSystem --suppress=unusedFunction

# ****************************************************
# Targets needed to bring the executable up to date

all: $(OBJS)
        $(LD) -o $(TARGET) $(OBJS) $(LDFLAGS) $(LIBS) $(LDLIBS)

cppcheck:
        cppcheck $(CPP_OPTIONS) $(SRCS)

%.o: %.c
        $(CC) -c -o $(@F) $(CFLAGS) -DGIT_DATE='"$(GIT_DATE)"' $<

clean:
        rm -rf $(TARGET) *.o *.bin

# =============================================================================
# BEGIN GPIOD AUTO-DETECT (added by patch-trixie-gpiod.sh)
# Detect libgpiod major version and select appropriate source for g2panel.o
# =============================================================================
PKGCFG ?= pkg-config
GPIOD_VER := $(shell $(PKGCFG) --modversion libgpiod 2>/dev/null || echo 0.0.0)
GPIOD_MAJ := $(firstword $(subst ., ,$(GPIOD_VER)))
$(info libgpiod detected: $(GPIOD_VER))

CFLAGS  += $(shell $(PKGCFG) --cflags libgpiod)
LDLIBS  += $(shell $(PKGCFG) --libs   libgpiod)

ifeq ($(GPIOD_MAJ),2)
  G2PANEL_SRC := g2panel_v2.c
else
  G2PANEL_SRC := g2panel_v1.c
endif
$(info building with $(G2PANEL_SRC))

g2panel.o: $(G2PANEL_SRC) g2panel.h
        $(CC) $(CFLAGS) -c $< -o $@

# =============================================================================
# END GPIOD AUTO-DETECT (added by patch-trixie-gpiod.sh)
# =============================================================================
