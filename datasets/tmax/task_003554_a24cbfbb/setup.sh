#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ nginx wget curl
    pip3 install pytest requests

    mkdir -p /app/libfastcrc-1.2

    cat << 'EOF' > /app/libfastcrc-1.2/fastcrc.c
#include "fastcrc.h"
unsigned int compute_crc32c(const unsigned char *data, unsigned long length) {
    unsigned int crc = 0xFFFFFFFF;
    for (unsigned long i = 0; i < length; i++) {
        crc ^= data[i];
        for (int j = 0; j < 8; j++) {
            crc = (crc >> 1) ^ ((crc & 1) ? 0x82F63B78 : 0);
        }
    }
    return ~crc;
}
EOF

    cat << 'EOF' > /app/libfastcrc-1.2/fastcrc.h
#ifndef FASTCRC_H
#define FASTCRC_H
unsigned int compute_crc32c(const unsigned char *data, unsigned long length);
#endif
EOF

    cat << 'EOF' > /app/libfastcrc-1.2/Makefile
libfastcrc.so: fastcrc.c
	gcc -O0 -o libfastcrc.so fastcrc.c
EOF

    wget -q https://raw.githubusercontent.com/yhirose/cpp-httplib/v0.14.1/httplib.h -O /app/httplib.h

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
