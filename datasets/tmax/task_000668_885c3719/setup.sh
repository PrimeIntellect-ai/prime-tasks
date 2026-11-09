#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/artifact_encoder
    mkdir -p /home/user/pipeline/raw_artifacts
    mkdir -p /home/user/pipeline/encoded_artifacts

    cat << 'EOF' > /home/user/artifact_encoder/encoder.c
#include "encoder.h"

int process_data(const unsigned char* input, int length, unsigned char* output) {
    for(int i=0; i<length; i++) {
        output[i] = input[i] ^ 0x42; // XOR encoding with 0x42
    }
    return length;
}
EOF

    cat << 'EOF' > /home/user/artifact_encoder/encoder.h
#ifndef ENCODER_H
#define ENCODER_H

int process_data(const unsigned char* input, int length, unsigned char* output);

#endif
EOF

    cat << 'EOF' > /home/user/artifact_encoder/Makefile
CC=gcc
CFLAGS=-Wall

all: encoder

encoder: encoder.o
	$(CC) $(CFLAGS) -o encoder encoder.o

encoder.o: encoder.c
	$(CC) $(CFLAGS) -c encoder.c

clean:
	rm -f *.o encoder
EOF

    echo -n "Test artifact 1" > /home/user/pipeline/raw_artifacts/artifact1.bin
    echo -n "Hello CI/CD pipeline!" > /home/user/pipeline/raw_artifacts/artifact2.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
