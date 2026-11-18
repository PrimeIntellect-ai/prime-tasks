#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/pr_review

    cat << 'EOF' > /home/user/pr_review/checksum.c
#include <stdint.h>
#include <stdio.h>

uint32_t calculate_crc32(const char *filename) {
    FILE *f = fopen(filename, "rb");
    if (!f) return 0;

    uint32_t crc = 0xFFFFFFFF;
    int ch;
    while ((ch = fgetc(f)) != EOF) {
        crc ^= (uint32_t)ch;
        for (int i = 0; i < 8; i++) {
            crc = (crc >> 1) ^ (0xEDB88320 & (-(crc & 1)));
        }
    }
    fclose(f);
    return ~crc;
}
EOF

    cat << 'EOF' > /home/user/pr_review/main.c
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

extern uint32_t calculate_crc32(const char *filename);

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <file> <expected_crc32_hex>\n", argv[0]);
        return 1;
    }

    uint32_t actual_crc = calculate_crc32(argv[1]);
    uint32_t expected_crc = (uint32_t)strtoul(argv[2], NULL, 16);

    if (actual_crc == expected_crc) {
        printf("Checksum verified!\n");
        return 0;
    } else {
        printf("Checksum mismatch. Expected %08x, got %08x\n", expected_crc, actual_crc);
        return 1;
    }
}
EOF

    cat << 'EOF' > /home/user/pr_review/Makefile
CC = gcc
CFLAGS = -Wall -fPIC

all: verifier

libchecksum.so: checksum.c
	$(CC) $(CFLAGS) -shared -o libchecksum.so checksum.c

verifier: main.c libchecksum.so
	$(CC) -Wall -o verifier main.c

clean:
	rm -f *.o *.so verifier mock_data.bin test_result.log
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
