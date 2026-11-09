#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ make
    pip3 install pytest websockets

    mkdir -p /home/user/project
    cd /home/user/project

    cat << 'EOF' > libencoder.h
#ifndef LIBENCODER_H
#define LIBENCODER_H

char* hex_encode(const char* input);

#endif
EOF

    cat << 'EOF' > libencoder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "libencoder.h"

char* hex_encode(const char* input) {
    int len = strlen(input);
    // BUG: Allocating exactly len * 2, no space for null terminator.
    char* out = (char*)malloc(len * 2);
    for(int i = 0; i < len; i++) {
        sprintf(out + (i * 2), "%02X", (unsigned char)input[i]);
    }
    return out;
}
EOF

    cat << 'EOF' > wrapper.cpp
#include "libencoder.h"
#include <cstring>
#include <cstdlib>

extern "C" {
    char* encode_string(const char* in) {
        return hex_encode(in);
    }
}
EOF

    cat << 'EOF' > Makefile
all: libencoder.so wrapper.so

libencoder.so: libencoder.c
	gcc -o libencoder.so libencoder.c

wrapper.so: wrapper.cpp libencoder.so
	g++ -o wrapper.so wrapper.cpp -L. -lencoder
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
