CC=gcc
CFLAGS=-O2 -Wall -Wextra
GTK_CFLAGS=$(shell pkg-config --cflags gtk+-3.0)
GTK_LIBS=$(shell pkg-config --libs gtk+-3.0)

BIN=p2app-control
SRC=src/p2app_control.c

all: $(BIN)

$(BIN): $(SRC)
	$(CC) $(CFLAGS) $(GTK_CFLAGS) -o $@ $< $(GTK_LIBS)

clean:
	rm -f $(BIN)

install: $(BIN)
	install -D -m 0755 $(BIN) /usr/local/bin/$(BIN)
	install -D -m 0755 P2_app-Control.desktop /home/pi/Desktop/P2_app-Control.desktop

.PHONY: all clean install
