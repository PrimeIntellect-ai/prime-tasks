#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc zlib1g-dev
    pip3 install pytest requests

    mkdir -p /home/user/spool
    mkdir -p /app

    cat << 'EOF' > /tmp/cpk_tool.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <zlib.h>

int main() {
    uint8_t header[16];
    if (fread(header, 1, 16, stdin) != 16) return 1;
    if (memcmp(header, "CPK\x01", 4) != 0) return 1;

    uint32_t len = header[8] | (header[9] << 8) | (header[10] << 16) | (header[11] << 24);
    uint32_t crc_val = header[12] | (header[13] << 8) | (header[14] << 16) | (header[15] << 24);

    if (len > 1024*1024*10) return 1;

    uint8_t *comp_data = malloc(len);
    if (!comp_data) return 1;
    if (fread(comp_data, 1, len, stdin) != len) return 1;

    uLong crc = crc32(0L, Z_NULL, 0);
    crc = crc32(crc, comp_data, len);
    if (crc != crc_val) return 1;

    uLongf destLen = 1024*1024*50;
    uint8_t *dest = malloc(destLen);
    if (!dest) return 1;
    if (uncompress(dest, &destLen, comp_data, len) != Z_OK) return 1;

    fwrite(dest, 1, destLen, stdout);
    return 0;
}
EOF

    gcc -O2 -s /tmp/cpk_tool.c -o /app/cpk_tool -lz
    rm /tmp/cpk_tool.c

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
