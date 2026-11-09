#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential zip unzip
    pip3 install pytest

    mkdir -p /app/simple-elf-validator-0.1.0

    cat << 'EOF' > /app/simple-elf-validator-0.1.0/elf_validator.h
#ifndef ELF_VALIDATOR_H
#define ELF_VALIDATOR_H
bool is_valid_elf(const char* filepath);
#endif
EOF

    cat << 'EOF' > /app/simple-elf-validator-0.1.0/elf_validator.cpp
#include "elf_validator.h"
#include <fstream>
#include <iostream>

bool is_valid_elf(const char* filepath) {
    std::ifstream file(filepath, std::ios::binary);
    if (!file) return false;
    char magic[4];
    if (file.read(magic, 4)) {
        return magic[0] == 0x7f && magic[1] == 'E' && magic[2] == 'L' && magic[3] == 'F';
    }
    return false;
}
EOF

    cat << 'EOF' > /app/simple-elf-validator-0.1.0/Makefile
CC=gcc
CFLAGS=-Wall -Wextra -O2

all: libelfval.a

elf_validator.o: elf_validator.cpp
	$(CC) $(CFLAGS) -c elf_validator.cpp -o elf_validator.o

libelfval.a: elf_validator.o
	ar rcs libelfval.a elf_validator.o

clean:
	rm -f *.o *.a
EOF

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil
    mkdir -p /app/hidden_corpus/clean
    mkdir -p /app/hidden_corpus/evil

    echo "int main() { return 0; }" > /tmp/dummy.c
    gcc /tmp/dummy.c -o /tmp/dummy_elf

    for i in $(seq 1 50); do
        cp /tmp/dummy_elf /app/hidden_corpus/clean/elf_$i
        echo "not an elf $i" > /app/hidden_corpus/evil/bad_$i
        if [ $i -le 10 ]; then
            cp /tmp/dummy_elf /app/corpus/clean/elf_$i
            echo "not an elf $i" > /app/corpus/evil/bad_$i
        fi
    done

    cd /app/corpus
    zip -r /app/corpus.zip clean evil
    cd /
    rm -rf /app/corpus /tmp/dummy.c /tmp/dummy_elf

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
