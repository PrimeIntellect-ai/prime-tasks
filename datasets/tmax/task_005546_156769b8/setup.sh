#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl gcc make jq golang-go build-essential
    pip3 install pytest

    # Install Rust minimally
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
    export PATH="/root/.cargo/bin:${PATH}"

    mkdir -p /home/user/workspace/legacy_crypto
    cd /home/user/workspace/legacy_crypto

    cat << 'EOF' > crypto.h
#ifndef CRYPTO_H
#define CRYPTO_H

void apply_mask(const char* input, char* output);

#endif
EOF

    cat << 'EOF' > crypto.c
#include "crypto.h"
#include <string.h>

void apply_mask(const char* input, char* output) {
    int len = strlen(input);
    for(int i = 0; i < len; i++) {
        output[i] = input[i] ^ 0x2A; // Simple XOR mask for testing
    }
    output[len] = '\0';
}
EOF

    cat << 'EOF' > Makefile
# Broken Makefile
CC=gcc
CFLAGS=-Wall

all: libcrypto_mask.so

libcrypto_mask.so: crypto.o
	$(CC) -o libcrypto_mask.so crypto.o

crypto.o: crypto.c
	$(CC) $(CFLAGS) -c crypto.c
EOF

    useradd -m -s /bin/bash user || true

    # Make sure Rust is available for the user
    cp -r /root/.cargo /root/.rustup /home/user/ || true
    chown -R user:user /home/user/.cargo /home/user/.rustup || true
    echo 'export PATH="/home/user/.cargo/bin:${PATH}"' >> /home/user/.bashrc

    chmod -R 777 /home/user
