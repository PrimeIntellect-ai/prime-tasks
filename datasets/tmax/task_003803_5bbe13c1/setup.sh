#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/header_parser.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

static uint32_t crc32_table[256];
static int crc_table_computed = 0;

static void make_crc_table(void) {
    uint32_t c;
    int n, k;
    for (n = 0; n < 256; n++) {
        c = (uint32_t) n;
        for (k = 0; k < 8; k++) {
            if (c & 1) c = 0xedb88320L ^ (c >> 1);
            else c = c >> 1;
        }
        crc32_table[n] = c;
    }
    crc_table_computed = 1;
}

static uint32_t update_crc32(uint32_t crc, const unsigned char *buf, size_t len) {
    uint32_t c = crc ^ 0xffffffffL;
    size_t n;
    if (!crc_table_computed) make_crc_table();
    for (n = 0; n < len; n++) {
        c = crc32_table[(c ^ buf[n]) & 0xff] ^ (c >> 8);
    }
    return c ^ 0xffffffffL;
}

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);

    if (size < 16) {
        printf("ERROR: TOO_SHORT\n");
        fclose(f);
        return 0;
    }

    unsigned char header[16];
    if (fread(header, 1, 16, f) != 16) {
        fclose(f);
        return 1;
    }

    if (header[0] != 0x50 || header[1] != 0x44 || header[2] != 0x41 || header[3] != 0x54) {
        printf("ERROR: BAD_MAGIC\n");
        fclose(f);
        return 0;
    }

    uint32_t ts = header[4] | (header[5] << 8) | (header[6] << 16) | (header[7] << 24);
    uint16_t dev = (header[8] << 8) | header[9];
    uint16_t exp = header[10] | (header[11] << 8);
    uint32_t crc_hdr = header[12] | (header[13] << 8) | (header[14] << 16) | (header[15] << 24);

    uint32_t calc_crc = 0;
    if (size > 16) {
        unsigned char *payload = malloc(size - 16);
        if (fread(payload, 1, size - 16, f) == size - 16) {
            calc_crc = update_crc32(0, payload, size - 16);
        }
        free(payload);
    }

    const char *integrity = (calc_crc == crc_hdr) ? "VALID" : "INVALID";
    printf("TS:%u DEV:%u EXP:%u INTEGRITY:%s\n", ts, dev, exp, integrity);

    fclose(f);
    return 0;
}
EOF

    gcc -O2 /app/header_parser.c -o /app/header_parser
    strip /app/header_parser
    rm /app/header_parser.c

    mkdir -p /home/user/raw_data
    cat << 'EOF' > /tmp/gen_data.py
import os
import struct
import zlib
import random

os.makedirs('/home/user/raw_data', exist_ok=True)

for i in range(20):
    with open(f'/home/user/raw_data/file_{i}.dat', 'wb') as f:
        if i < 2:
            # Short file
            f.write(os.urandom(random.randint(0, 15)))
        elif i < 5:
            # Bad magic
            f.write(os.urandom(16 + random.randint(0, 100)))
        else:
            # Valid header structure
            payload = os.urandom(random.randint(0, 100))
            ts = random.randint(0, 0xFFFFFFFF)
            dev = random.randint(0, 0xFFFF)
            exp = random.randint(0, 0xFFFF)

            # 50% valid crc
            if i % 2 == 0:
                crc = zlib.crc32(payload)
            else:
                crc = random.randint(0, 0xFFFFFFFF)

            header = b'PDAT'
            header += struct.pack('<I', ts)
            header += struct.pack('>H', dev)
            header += struct.pack('<H', exp)
            header += struct.pack('<I', crc)
            f.write(header + payload)
EOF

    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
