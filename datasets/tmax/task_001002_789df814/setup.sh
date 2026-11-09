#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    # Create libwalparse directory
    mkdir -p /app/libwalparse-1.0

    # Create walparse.h
    cat << 'EOF' > /app/libwalparse-1.0/walparse.h
#ifndef WALPARSE_H
#define WALPARSE_H

#include <stdint.h>
#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

int parse_wal_frame(FILE* in, uint32_t* page_id, uint8_t** data, uint16_t* len);

#ifdef __cplusplus
}
#endif

#endif
EOF

    # Create walparse.c (with stdlib.h for building the oracle)
    cat << 'EOF' > /app/libwalparse-1.0/walparse.c
#include "walparse.h"
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

int parse_wal_frame(FILE* in, uint32_t* page_id, uint8_t** data, uint16_t* len) {
    uint32_t magic;
    if (fread(&magic, 4, 1, in) != 1) return 0;
    if (magic != 0x57414C21) return 0;

    if (fread(page_id, 4, 1, in) != 1) return 0;
    if (fread(len, 2, 1, in) != 1) return 0;

    *data = (uint8_t*)malloc(*len);
    if (!*data) return 0;

    if (fread(*data, 1, *len, in) != *len) {
        free(*data);
        return 0;
    }

    return 1;
}
EOF

    # Create Makefile
    cat << 'EOF' > /app/libwalparse-1.0/Makefile
CC = gcc
CFLAGS = -Wall -Werror=implicit-function-declaration -O2

all: libwalparse.a

libwalparse.a: walparse.o
	ar rcs $@ $^

walparse.o: walparse.c walparse.h
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f *.o *.a
EOF

    # Create oracle
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/oracle.cpp
#include <iostream>
#include <cstdio>
#include <cstdlib>
#include "walparse.h"

int main() {
    uint32_t page_id;
    uint8_t* data;
    uint16_t len;

    while (parse_wal_frame(stdin, &page_id, &data, &len)) {
        if (page_id % 2 == 0) {
            uint8_t xor_sum = 0;
            for (int i = 0; i < len; ++i) {
                xor_sum ^= data[i];
            }
            fwrite(&page_id, 4, 1, stdout);
            fwrite(&xor_sum, 1, 1, stdout);
        }
        free(data);
    }
    return 0;
}
EOF

    # Build oracle
    cd /app/libwalparse-1.0
    make
    g++ -O2 -I/app/libwalparse-1.0 /opt/oracle/oracle.cpp /app/libwalparse-1.0/libwalparse.a -o /opt/oracle/wal_archiver
    make clean

    # Perturb walparse.c (remove stdlib.h)
    cat << 'EOF' > /app/libwalparse-1.0/walparse.c
#include "walparse.h"
#include <stdio.h>
#include <stdint.h>

int parse_wal_frame(FILE* in, uint32_t* page_id, uint8_t** data, uint16_t* len) {
    uint32_t magic;
    if (fread(&magic, 4, 1, in) != 1) return 0;
    if (magic != 0x57414C21) return 0;

    if (fread(page_id, 4, 1, in) != 1) return 0;
    if (fread(len, 2, 1, in) != 1) return 0;

    *data = (uint8_t*)malloc(*len);
    if (!*data) return 0;

    if (fread(*data, 1, *len, in) != *len) {
        free(*data);
        return 0;
    }

    return 1;
}
EOF

    # Clean up oracle source
    rm /opt/oracle/oracle.cpp

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
