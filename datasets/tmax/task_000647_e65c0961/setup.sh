#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/suspicious.log
[2024-05-12 08:11:22] Connection from 192.168.1.50 - Auth failed (Seed: 10293)
[2024-05-12 09:14:05] Connection from 203.0.113.42 - Auth success (Seed: 84729)
[2024-05-12 10:00:01] Connection from 10.0.0.5 - Auth failed (Seed: 55431)
[2024-05-12 11:22:33] Connection from 172.16.0.4 - Auth failed (Seed: 99120)
EOF

    cat << 'EOF' > /home/user/auth_logic.c
#include <stdint.h>

uint32_t validate_token(uint32_t seed, uint32_t provided_token) {
    uint32_t step1 = seed ^ 0xCAFEBABE;
    uint32_t step2 = (step1 << 3) | (step1 >> 29);
    uint32_t expected = step2 + 0x1337;

    return provided_token == expected;
}
EOF

    chmod -R 777 /home/user
