#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/config_store
    cat << 'EOF' > /home/user/base_config.log
[2024-01-01 10:00:00] CONFIG_ADD MAX_CONNECTIONS 100
[2024-01-01 10:01:00] CONFIG_ADD TIMEOUT_MS 5000
[2024-01-01 10:02:00] CONFIG_ADD RETRY_COUNT 3
EOF

    mkdir -p /app
    cat << 'EOF' > /app/cfg_checksum_source.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

uint32_t crc32(const unsigned char *s, size_t n) {
    uint32_t crc = 0xFFFFFFFF;
    for (size_t i = 0; i < n; i++) {
        crc ^= s[i];
        for (int j = 0; j < 8; j++) {
            crc = (crc >> 1) ^ (0xEDB88320 & (-(crc & 1)));
        }
    }
    return ~crc;
}

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    fseek(f, 0, SEEK_END);
    long fsize = ftell(f);
    fseek(f, 0, SEEK_SET);
    unsigned char *string = malloc(fsize);
    if (fsize > 0 && fread(string, fsize, 1, f) != 1) {
        free(string);
        fclose(f);
        return 1;
    }
    fclose(f);

    uint32_t c = crc32(string, fsize);
    printf("%u\n", c ^ 0xDEADBEEF);
    free(string);
    return 0;
}
EOF

    gcc -O2 -s /app/cfg_checksum_source.c -o /app/cfg_checksum
    rm /app/cfg_checksum_source.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
