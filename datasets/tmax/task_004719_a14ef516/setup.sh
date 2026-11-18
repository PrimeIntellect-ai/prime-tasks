#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake build-essential
    pip3 install pytest Flask websockets requests

    mkdir -p /home/user/polyglot_auth/lib
    mkdir -p /home/user/polyglot_auth/src
    mkdir -p /home/user/polyglot_auth/tests

    cat << 'EOF' > /home/user/polyglot_auth/lib/secure_hash.c
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include "secure_hash.h"

void compute_hash(const char* input, char* output) {
    int len = strlen(input);
    // BUG: Allocating exactly len bytes, missing +1 for null terminator
    char* temp = malloc(len);

    for (int i = 0; i < len; i++) {
        temp[i] = input[i] ^ 0x42; // simple XOR hash
    }
    temp[len] = '\0'; // Undefined behavior: out of bounds write!

    for (int i = 0; i < len; i++) {
        sprintf(output + (i * 2), "%02x", (unsigned char)temp[i]);
    }
    free(temp);
}
EOF

    cat << 'EOF' > /home/user/polyglot_auth/lib/secure_hash.h
#ifndef SECURE_HASH_H
#define SECURE_HASH_H

void compute_hash(const char* input, char* output);

#endif
EOF

    cat << 'EOF' > /home/user/polyglot_auth/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(PolyglotAuth)

# BUG: Building static instead of shared
add_library(secure_hash STATIC lib/secure_hash.c)
target_include_directories(secure_hash PUBLIC lib)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
