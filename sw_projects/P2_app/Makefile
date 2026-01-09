# Makefile for p2app
# *****************************************************
# Variables to control Makefile operation

CC = gcc
LD = gcc
CFLAGS = -Wall -Wextra -Wno-unused-function -g -D_GNU_SOURCE
LDFLAGS = -lm -lpthread

# NOTE (2026-01): keep "local" libs here. libgpiod link flags are added below
#                 via pkg-config (with a safe fallback).
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
	$(LD) -o $(TARGET) $(OBJS) $(LDFLAGS) $(LIBS)

cppcheck:
	cppcheck $(CPP_OPTIONS) $(SRCS)

%.o: %.c
	$(CC) -c -o $(@F) $(CFLAGS) -D GIT_DATE='"$(GIT_DATE)"' $<

clean:
	rm -rf $(TARGET) *.o *.bin

# =============================================================================
# BEGIN GPIOD AUTO-DETECT (repo maintained)
# Detect libgpiod major version and select appropriate source for g2panel.o
# =============================================================================
# NOTE (2026-01):
#   * No scripts should generate/overwrite any .c files at build time.
#   * This Makefile selects the correct panel GPIO implementation based on
#     the installed libgpiod major version.

PKGCFG ?= pkg-config

# Version detection (works on both v1 and v2 installs when pkg-config is present)
GPIOD_VER := $(shell $(PKGCFG) --modversion libgpiod 2>/dev/null || echo 0.0.0)
GPIOD_MAJ := $(firstword $(subst ., ,$(GPIOD_VER)))
$(info libgpiod detected: $(GPIOD_VER))

# Pull build flags from pkg-config (quietly, to avoid breaking older installs)
GPIOD_CFLAGS := $(shell $(PKGCFG) --cflags libgpiod 2>/dev/null)
GPIOD_LIBS   := $(shell $(PKGCFG) --libs   libgpiod 2>/dev/null)

# Fallback if pkg-config is unavailable (keeps older distros working)
ifeq ($(strip $(GPIOD_LIBS)),)
  GPIOD_LIBS := -lgpiod
endif

CFLAGS += $(GPIOD_CFLAGS)
LIBS   += $(GPIOD_LIBS)

# Treat libgpiod major version 2+ as the 'v2' API family
GPIOD_IS_V2PLUS := $(shell [ "$(GPIOD_MAJ)" -ge 2 ] 2>/dev/null && echo 1 || echo 0)

ifeq ($(GPIOD_IS_V2PLUS),1)
  G2PANEL_SRC := g2panel_libgpiodv2.c
else
  # libgpiod v1.x
  G2PANEL_SRC := g2panel.c
endif

$(info building with $(G2PANEL_SRC))

# Build g2panel.o from the selected source file (output name stays g2panel.o)
g2panel.o: $(G2PANEL_SRC) g2panel.h
	$(CC) $(CFLAGS) -c $< -o $@

# =============================================================================
# END GPIOD AUTO-DETECT (repo maintained)
# =============================================================================
