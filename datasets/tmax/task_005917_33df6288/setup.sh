#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libc6-dev openssl cppcheck
    pip3 install pytest

    mkdir -p /home/user/packet_analysis

    cat << 'EOF' > /home/user/packet_analysis/parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

int main(int argc, char **argv) {
    if (argc != 3) {
        printf("Usage: %s <input.bin> <output.enc>\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    char magic[5] = {0};
    fread(magic, 1, 4, f);
    if (strncmp(magic, "PCKT", 4) != 0) {
        printf("Invalid magic\n");
        return 1;
    }

    uint32_t len = 0;
    fread(&len, 4, 1, f);

    // VULNERABILITY: Static buffer of 256 bytes, but 'len' can be much larger.
    char buffer[256];
    fread(buffer, 1, len, f);

    FILE *out = fopen(argv[2], "wb");
    if (!out) return 1;

    fwrite(buffer, 1, len, out);

    fclose(out);
    fclose(f);
    return 0;
}
EOF

    cd /home/user/packet_analysis
    openssl req -x509 -newkey rsa:2048 -keyout dummy.key -out dummy.crt -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Org/CN=dummy.local" 2>/dev/null

    cat << 'EOF' > generate_capture.py
import struct
import os

key = b"s3cr3t"

with open("dummy.crt", "rb") as f:
    plaintext = f.read()

# XOR encrypt
ciphertext = bytearray()
for i in range(len(plaintext)):
    ciphertext.append(plaintext[i] ^ key[i % len(key)])

with open("capture.bin", "wb") as f:
    f.write(b"PCKT")
    f.write(struct.pack("<I", len(ciphertext)))
    f.write(ciphertext)
EOF

    python3 generate_capture.py

    openssl x509 -in dummy.crt -noout -fingerprint -sha256 | cut -d'=' -f2 > /home/user/packet_analysis/expected_fingerprint.txt

    rm dummy.key dummy.crt generate_capture.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
