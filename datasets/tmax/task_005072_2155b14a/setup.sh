#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/math_project
cd /home/user/math_project

cat << 'EOF' > encoder.h
#ifndef ENCODER_H
#define ENCODER_H

#include "decoder.h"

struct EncodedData {
    char hex_output[256];
    struct DecodedData* original;
};

void encode_data(int shift, const char* data, char* output);

#endif
EOF

cat << 'EOF' > decoder.h
#ifndef DECODER_H
#define DECODER_H

#include "encoder.h"

struct DecodedData {
    char raw_text[128];
    struct EncodedData* encoded;
};

void decode_data(const char* hex_data, char* output);

#endif
EOF

cat << 'EOF' > encoder.c
#include "encoder.h"
#include <stdio.h>
#include <string.h>

void encode_data(int shift, const char* data, char* output) {
    // TODO: Implement modulo-256 mathematical shift and uppercase hex encoding
}
EOF

cat << 'EOF' > decoder.c
#include "decoder.h"

void decode_data(const char* hex_data, char* output) {
    // Not required for this task
}
EOF

cat << 'EOF' > main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "encoder.h"

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Missing URL argument\n");
        return 1;
    }

    char* url = argv[1];

    // TODO: Parse the route, shift, and data from the URL
    // e.g., /api/encode?shift=5&data=Test
    // If route != "/api/encode", print "404 Not Found" and exit 1

    int shift = 0;
    char data[128] = {0};

    // Extracted logic goes here

    char hex_output[256] = {0};
    // encode_data(shift, data, hex_output);
    // printf("%s\n", hex_output);

    return 0;
}
EOF

cat << 'EOF' > Makefile
CC=gcc
CFLAGS=-Wall -Wextra

all: math_router

math_router: main.o encoder.o decoder.o
	$(CC) $(CFLAGS) -o math_router main.o encoder.o decoder.o

main.o: main.c encoder.h
	$(CC) $(CFLAGS) -c main.c

encoder.o: encoder.c encoder.h decoder.o
	$(CC) $(CFLAGS) -c encoder.c

decoder.o: decoder.c decoder.h encoder.o
	$(CC) $(CFLAGS) -c decoder.c

clean:
	rm -f *.o math_router
EOF

chmod -R 777 /home/user
