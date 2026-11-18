#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app/bin
    mkdir -p /var/opt/clean_corpus /var/opt/evil_corpus

    cat << 'EOF' > /tmp/decoder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    char *hex = argv[1];
    size_t len = strlen(hex);
    if (len != 8) return 1;

    uint8_t bytes[4];
    for (int i = 0; i < 4; i++) {
        sscanf(hex + 2*i, "%2hhx", &bytes[i]);
        bytes[i] ^= 0x42;
    }

    uint32_t ts = *(uint32_t*)bytes;
    printf("%u\n", ts);
    return 0;
}
EOF
    gcc -O2 /tmp/decoder.c -o /app/bin/temporal_decoder
    strip /app/bin/temporal_decoder
    chmod +x /app/bin/temporal_decoder
    rm /tmp/decoder.c

    cat << 'EOF' > /tmp/generate_data.py
import os
import json
import struct

def encode_ts(ts):
    b = struct.pack('<I', ts)
    return ''.join(f'{x ^ 0x42:02x}' for x in b)

for i in range(50):
    with open(f'/var/opt/clean_corpus/clean_{i}.jsonl', 'w') as f:
        for j in range(20):
            ts = 1700000000 + j * 10
            event = {
                "user_id": f"u{i}",
                "obfuscated_ts": encode_ts(ts),
                "event_type": "LOGIN_SUCCESS",
                "ip_address": f"192.168.1.{j%2}"
            }
            f.write(json.dumps(event) + '\n')

for i in range(50):
    with open(f'/var/opt/evil_corpus/evil_{i}.jsonl', 'w') as f:
        if i < 15:
            event = {"user_id": "u1", "obfuscated_ts": encode_ts(1700000000), "event_type": "LOGIN"}
            f.write(json.dumps(event) + '\n')
        elif i < 35:
            for j in range(5):
                event = {
                    "user_id": "u1",
                    "obfuscated_ts": encode_ts(1700000000 + j),
                    "event_type": "LOGIN",
                    "ip_address": f"10.0.0.{j}"
                }
                f.write(json.dumps(event) + '\n')
        else:
            for j in range(12):
                event = {
                    "user_id": f"u{j}",
                    "obfuscated_ts": encode_ts(1700000000 + j),
                    "event_type": "LOGIN_FAILED",
                    "ip_address": "10.0.0.1"
                }
                f.write(json.dumps(event) + '\n')
EOF
    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
