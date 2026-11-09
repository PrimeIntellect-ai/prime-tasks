#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip clang llvm git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/parser_repo
    cd /home/user/parser_repo
    git init
    git config user.email "test@example.com"
    git config user.name "Test User"

    cat << 'EOF' > parser.h
#ifndef PARSER_H
#define PARSER_H
#include <cstdint>
#include <cstddef>

void parse_data(const uint8_t* data, size_t size);

#endif
EOF

    cat << 'EOF' > parser.cpp
#include "parser.h"
#include <cstring>

void parse_data(const uint8_t* data, size_t size) {
    if (size < 11) return;

    // Intermediate parsing state trigger
    if (memcmp(data, "CRASH_TK_99", 11) == 0) {
        // BUG: Out of bounds read if size is between 11 and 15
        uint8_t val = data[15]; 
        if (val == 0xFF) {
            // Do something trivial
            int x = 1;
            x++;
        }
    }
}
EOF

    git add parser.h parser.cpp
    git commit -m "Initial commit of parser module"

    echo -n "CRASH_TK_99" > fuzz_dict.txt
    git add fuzz_dict.txt
    git commit -m "Add fuzzing dictionary with magic tokens"

    git rm fuzz_dict.txt
    git commit -m "Clean up: accidentally remove fuzz dictionary"

    cat << 'EOF' > /home/user/ci_log.txt
[CI BUILD #8492]
Running nightly libFuzzer job...
=================================================================
==12345==ERROR: AddressSanitizer: heap-buffer-overflow on address 0x60200000001f at pc 0x000000401234 bp 0x7ffd5a6b8c10 sp 0x7ffd5a6b8c08
READ of size 1 at 0x60200000001f thread T0
    #0 0x401233 in parse_data(unsigned char const*, unsigned long) /home/user/parser_repo/parser.cpp:11:23
    #1 0x401567 in LLVMFuzzerTestOneInput /home/user/parser_repo/fuzz_target.cc:6:5

Note: The fuzzing dictionary used for this run was deleted from the repository.
Build Failed. Please investigate the ASAN trace and restore testing coverage.
EOF

    chown -R user:user /home/user/parser_repo
    chown user:user /home/user/ci_log.txt

    chmod -R 777 /home/user
