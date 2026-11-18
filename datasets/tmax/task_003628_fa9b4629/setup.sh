#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make netcat-openbsd socat coreutils bash
    pip3 install pytest

    mkdir -p /app/extractor

    cat << 'EOF' > /app/extractor/main.c
#include <stdio.h>
#include "dsp.h"
int main(int argc, char **argv) {
    if (argc < 2) return 1;
    // Mock extraction logic simulating reading the audio file
    // dsp_process uses math library just to force linking requirement
    dsp_process();
    printf("LOAD 100\nADD 50\nDIV 3\nSUB 8\nMUL 2\n");
    return 0;
}
EOF

    cat << 'EOF' > /app/extractor/dsp.c
#include <math.h>
#include "dsp.h"
void dsp_process() {
    volatile double x = sqrt(16.0);
}
EOF

    cat << 'EOF' > /app/extractor/dsp.h
#ifndef DSP_H
#define DSP_H
void dsp_process();
#endif
EOF

    cat << 'EOF' > /app/extractor/Makefile
all: extractor
extractor: main.o dsp.o
	gcc -o extractor main.o dsp.o
main.o: main.c
	gcc -c main.c
dsp.o: dsp.c
	gcc -c dsp.c
clean:
	rm -f *.o extractor
EOF

    touch /app/fixture.wav

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
