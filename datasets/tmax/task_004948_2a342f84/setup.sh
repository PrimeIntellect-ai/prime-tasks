#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils strace gdb
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/wal_packer.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

uint32_t crc32(const uint8_t *data, size_t length) {
    uint32_t crc = 0xFFFFFFFF;
    for (size_t i = 0; i < length; i++) {
        crc ^= data[i];
        for (int j = 0; j < 8; j++) {
            if (crc & 1) crc = (crc >> 1) ^ 0xEDB88320;
            else crc >>= 1;
        }
    }
    return ~crc;
}

int main(int argc, char *argv[]) {
    if (argc != 3) return 1;
    FILE *fin = fopen(argv[1], "rb");
    if (!fin) return 1;

    fseek(fin, 0, SEEK_END);
    long size = ftell(fin);
    fseek(fin, 0, SEEK_SET);

    uint8_t *data = malloc(size);
    if (size > 0) {
        fread(data, 1, size, fin);
    }
    fclose(fin);

    char tmp_out[2048];
    snprintf(tmp_out, sizeof(tmp_out), "%s.tmp", argv[2]);
    FILE *fout = fopen(tmp_out, "wb");
    if (!fout) {
        free(data);
        return 1;
    }

    size_t i = 0;
    while (i < size) {
        uint8_t val = data[i];
        size_t count = 1;
        while (i + count < size && data[i + count] == val && count < 255) {
            count++;
        }
        if (count >= 3) {
            fputc(0xAA, fout);
            fputc(count, fout);
            fputc(val, fout);
            i += count;
        } else if (val == 0xAA) {
            fputc(0xAA, fout);
            fputc(0x01, fout);
            fputc(0xAA, fout);
            i++;
        } else {
            fputc(val, fout);
            i++;
        }
    }

    uint32_t crc = crc32(data, size);
    fwrite(&crc, 1, 4, fout);
    fclose(fout);

    rename(tmp_out, argv[2]);
    free(data);
    return 0;
}
EOF

    gcc -O2 /tmp/wal_packer.c -o /app/wal_packer
    strip /app/wal_packer
    rm /tmp/wal_packer.c

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/backup_data

    # Create sample WAL files
    for i in 1 2 3 4 5; do
        dd if=/dev/urandom of=/home/user/backup_data/sample${i}.wal bs=1024 count=$(( (RANDOM % 10) + 2 ))
    done

    chmod -R 777 /home/user
