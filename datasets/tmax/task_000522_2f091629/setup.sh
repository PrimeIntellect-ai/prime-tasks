#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git build-essential
    pip3 install pytest

    mkdir -p /home/user/db_triage
    cd /home/user/db_triage

    git config --global user.email "test@example.com"
    git config --global user.name "Test User"
    git init

    cat << 'EOF' > secret.h
#define RECOVERY_KEY "SuperSecretK3y!!"
EOF

    cat << 'EOF' > db_parser.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

int main(int argc, char** argv) {
    if (argc != 3) {
        printf("Usage: %s <journal_file> <key>\n", argv[0]);
        return 1;
    }
    // Buggy implementation that user must fix
    FILE* f = fopen(argv[1], "rb");
    if(!f) return 1;

    uint32_t magic, len;
    while(fread(&magic, 1, 4, f) == 4) {
        if(magic != 0xCAFEBABE) {
            fprintf(stderr, "Corrupted magic, aborting.\n");
            break; // Agent needs to fix this to scan forward
        }
        if(fread(&len, 1, 4, f) != 4) break;

        uint8_t* payload = malloc(len);
        fread(payload, 1, len, f);

        uint8_t checksum;
        fread(&checksum, 1, 1, f);

        // Decrypt and verify (agent needs to ensure recovery if this fails)
        uint32_t sum = 0;
        for(uint32_t i=0; i<len; i++) {
            payload[i] ^= argv[2][i % 16];
            sum += payload[i];
        }

        if((sum % 256) != checksum) {
            fprintf(stderr, "Checksum mismatch, aborting.\n");
            free(payload);
            break; // Agent needs to fix this
        }

        // Print payload (assume null terminated or print by len)
        printf("%.*s\n", len, payload);
        free(payload);
    }
    fclose(f);
    return 0;
}
EOF

    git add secret.h db_parser.c
    git commit -m "Initial commit with parser and config"

    git rm secret.h
    git commit -m "Remove hardcoded secret key"

    cat << 'EOF' > gen_bin.py
import struct

key = b"SuperSecretK3y!!"

def make_record(payload_str):
    payload = payload_str.encode('utf-8')
    decrypted_sum = sum(payload) % 256
    encrypted = bytearray()
    for i, b in enumerate(payload):
        encrypted.append(b ^ key[i % 16])

    res = struct.pack("<I", 0xCAFEBABE)
    res += struct.pack("<I", len(payload))
    res += encrypted
    res += struct.pack("B", decrypted_sum)
    return res

out = bytearray()
out += make_record("USER_1=ALICE")
out += make_record("USER_2=BOB")

# Insert corruption (the script that broke on spaces)
out += b"  GARBAGE SPACE CORRUPTION  \xCA\xFE" 

out += make_record("USER_3=CHARLIE")
out += make_record("USER_4=DAVE")

# More corruption
out += b"\x00\x00\x00\x00"

out += make_record("USER_5=EVE")

with open("corrupted journal with spaces.bin", "wb") as f:
    f.write(out)
EOF

    python3 gen_bin.py
    rm gen_bin.py

    git add "corrupted journal with spaces.bin"
    git commit -m "Add corrupted journal for triage"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
