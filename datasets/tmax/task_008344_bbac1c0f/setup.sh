#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gcc build-essential curl
    pip3 install pytest

    mkdir -p /home/user/legacy
    mkdir -p /home/user/api
    mkdir -p /home/user/proxy

    cat << 'EOF' > /home/user/legacy/secret.h
#ifndef SECRET_H
#define SECRET_H

const char* get_encoded_secret();

#endif
EOF

    cat << 'EOF' > /home/user/legacy/secret.c
#include "secret.h"

// The original secret is "API_KEY_998877"
// Hex of (char XOR 0x55)
const char* get_encoded_secret() {
    return "14051c0a1e100c0a6c6c6d6d6e6e";
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
