#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils golang-go
pip3 install pytest

mkdir -p /app

cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

uint32_t rc_crc32(uint32_t crc, const char *buf, size_t len) {
    static uint32_t table[256];
    static int have_table = 0;
    uint32_t rem;
    uint8_t octet;
    int i, j;
    const char *p, *q;

    if (have_table == 0) {
        for (i = 0; i < 256; i++) {
            rem = i;
            for (j = 0; j < 8; j++) {
                if (rem & 1) {
                    rem >>= 1;
                    rem ^= 0xedb88320;
                } else
                    rem >>= 1;
            }
            table[i] = rem;
        }
        have_table = 1;
    }

    crc = ~crc;
    q = buf + len;
    for (p = buf; p < q; p++) {
        octet = *p;
        crc = (crc >> 8) ^ table[(crc & 0xff) ^ octet];
    }
    return ~crc;
}

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    char hash_str[9] = {0};
    unsigned int port = 0;
    unsigned long long timestamp = 0;

    if (sscanf(argv[1], "%8[^:]:%u:%llu", hash_str, &port, &timestamp) != 3) {
        return 1;
    }

    uint32_t crc = rc_crc32(0, hash_str, 8);
    unsigned long long result = ((unsigned long long)crc * port) ^ timestamp;
    printf("%016llx\n", result);
    return 0;
}
EOF

gcc -O2 /tmp/oracle.c -o /app/audit_oracle
strip /app/audit_oracle
chmod +x /app/audit_oracle
rm /tmp/oracle.c

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
