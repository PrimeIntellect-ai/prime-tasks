#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git clang llvm gdb
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/suspicious_repo
    cd /home/user/suspicious_repo

    git config --global user.email "author@example.com"
    git config --global user.name "Author"
    git init

    # Create auth_math.h
    cat << 'EOF' > auth_math.h
#include <stdint.h>
uint32_t calculate_token(uint32_t timestamp);
EOF

    # Create auth_math.cpp
    cat << 'EOF' > auth_math.cpp
#include "auth_math.h"
#include "secret_params.h"

uint32_t calculate_token(uint32_t timestamp) {
    uint64_t internal_hash = (uint64_t)timestamp * SECRET_MULTIPLIER;
    uint32_t token = (internal_hash % 99991);

    // Mathematical flaw: specific modulo result causes crash
    if (token == 1337) {
        int* p = nullptr;
        *p = 42; // Crash here
    }

    return token;
}
EOF

    # Create secret_params.h
    cat << 'EOF' > secret_params.h
#define SECRET_MULTIPLIER 0x8a9b2c3d
EOF

    git add auth_math.cpp auth_math.h secret_params.h
    git commit -m "Initial commit with math logic"

    # Remove the secret
    git rm secret_params.h
    cat << 'EOF' > auth_math.cpp
#include "auth_math.h"
// #include "secret_params.h" // Removed for security

#define SECRET_MULTIPLIER 0x11223344 // Fake multiplier

uint32_t calculate_token(uint32_t timestamp) {
    uint64_t internal_hash = (uint64_t)timestamp * SECRET_MULTIPLIER;
    uint32_t token = (internal_hash % 99991);

    if (token == 1337) {
        int* p = nullptr;
        *p = 42; 
    }

    return token;
}
EOF
    git add auth_math.cpp
    git commit -m "Remove secrets"

    chmod -R 777 /home/user
