CFLAGS = -O3 -march=armv7-a -mtune=cortex-a9 -mfpu=neon -mfloat-abi=hard -D_GNU_SOURCE

all: p1app

p1app: p1app.c
	gcc $(CFLAGS) -o $@ $^ -lm -lpthread


clean:
	rm -f p1app

