#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bubblewrap gcc
    pip3 install pytest

    mkdir -p /app/corpora/clean /app/corpora/evil

    # Python script to generate the corpora
    cat << 'EOF' > /tmp/gen_corpora.py
import os
import struct

# Clean: completely random 16 bytes (32 hex chars) simulating strong tokens
for i in range(50):
    token = os.urandom(16).hex()
    with open(f"/app/corpora/clean/clean_{i}.txt", "w") as f:
        f.write(token)

# Evil: first 4 bytes XOR next 4 bytes = 0xDEADBEEF
for i in range(50):
    part1 = os.urandom(4)
    part2 = struct.pack(">I", struct.unpack(">I", part1)[0] ^ 0xDEADBEEF)
    part3 = os.urandom(8)
    token = (part1 + part2 + part3).hex()
    with open(f"/app/corpora/evil/evil_{i}.txt", "w") as f:
        f.write(token)
EOF
    python3 /tmp/gen_corpora.py

    # Create dummy stripped binary
    cat << 'EOF' > /tmp/auth.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    if (strlen(argv[1]) != 32) return 1;
    // Dummy acceptance
    return 0;
}
EOF
    gcc /tmp/auth.c -o /app/legacy_auth_service -s
    chmod +x /app/legacy_auth_service

    # Clean up
    rm /tmp/gen_corpora.py /tmp/auth.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
