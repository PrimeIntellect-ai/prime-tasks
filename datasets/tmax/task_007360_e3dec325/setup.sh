#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/evidence
    cd /home/user/evidence

    cat << 'EOF' > token.c
#include <stdint.h>

uint32_t generate_token(const char* pin, uint32_t challenge) {
    uint32_t hash = challenge;
    // Simple custom linear congruential hash
    for(int i=0; i<4; i++) {
        hash = (hash * 33) ^ pin[i];
    }
    return hash;
}
EOF

    gcc -shared -o libtoken.so -fPIC token.c
    rm token.c

    cat << 'EOF' > auth.log
[2023-10-12 14:00:01] Auth failed - Challenge: 1001, Token: 0x12345678
[2023-10-12 14:02:15] Auth failed - Challenge: 5542, Token: 0xaabbccdd
[2023-10-12 14:05:22] Auth success - Challenge: 84725, Token: 0x68b4466b
[2023-10-12 14:08:11] Auth failed - Challenge: 9912, Token: 0x11223344
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
