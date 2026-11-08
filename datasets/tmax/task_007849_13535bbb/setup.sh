#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make binutils libc6-dev
    pip3 install pytest

    mkdir -p /home/user/websec_project

    cat << 'EOF' > /home/user/websec_project/checksum.c
#include "checksum.h"

// Internal helper - MUST NOT be accessible from outside the shared library
unsigned int internal_mix_entropy(unsigned int hash, char c) {
    return (hash << 5) + hash + c;
}

// Public API - MUST be accessible from the shared library
unsigned int generate_web_token_hash(const char* input) {
    unsigned int hash = 5381;
    int c;
    while ((c = *input++)) {
        hash = internal_mix_entropy(hash, c);
    }
    return hash;
}
EOF

    cat << 'EOF' > /home/user/websec_project/checksum.h
#ifndef CHECKSUM_H
#define CHECKSUM_H
unsigned int generate_web_token_hash(const char* input);
#endif
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
