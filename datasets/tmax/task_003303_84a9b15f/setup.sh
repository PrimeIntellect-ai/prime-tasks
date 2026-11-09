#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak nasm gcc make
    pip3 install pytest

    # Create the audio file
    mkdir -p /app
    espeak -w /app/directive.wav "Build the server using API version two point one point zero. The cryptographic seed is five hundred eighty three."

    # Create the project files
    mkdir -p /home/user/project

    cat << 'EOF' > /home/user/project/libchecksum.c
#include <stdint.h>
#include <stddef.h>

extern uint32_t asm_checksum(const uint8_t *data, size_t len, uint32_t seed);

uint32_t compute_checksum(const uint8_t *data, size_t len, uint32_t seed) {
    return asm_checksum(data, len, seed);
}
EOF

    cat << 'EOF' > /home/user/project/checksum_x86_64.s
section .text
; Missing global declaration and implementation
; asm_checksum:
; ...
EOF

    cat << 'EOF' > /home/user/project/Makefile
CC=gcc
CFLAGS=-Wall -fPIC

all: libchecksum.so

checksum_x86_64.o: checksum_x86_64.s
	nasm -f elf64 checksum_x86_64.s -o checksum_x86_64.o

libchecksum.so: libchecksum.c checksum_x86_64.o
	$(CC) $(CFLAGS) -shared -o libchecksum.so libchecksum.c checksum_x86_64.o

clean:
	rm -f *.o *.so
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
