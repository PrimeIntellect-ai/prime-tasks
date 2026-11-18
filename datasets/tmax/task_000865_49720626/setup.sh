#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils gdb ltrace strace
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <ctype.h>

int hex_value(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

int main() {
    size_t capacity = 1024;
    uint8_t *hex_chars = malloc(capacity);
    size_t hex_len = 0;
    int c;
    while ((c = getchar()) != EOF) {
        if (isspace(c)) continue;
        int val = hex_value(c);
        if (val == -1) {
            printf("ERR: INVALID HEX\n");
            return 1;
        }
        if (hex_len >= capacity) {
            capacity *= 2;
            hex_chars = realloc(hex_chars, capacity);
        }
        hex_chars[hex_len++] = val;
    }
    if (hex_len % 2 != 0) {
        printf("ERR: INVALID HEX\n");
        return 1;
    }
    size_t byte_len = hex_len / 2;
    if (byte_len < 5) {
        printf("ERR: TOO SHORT\n");
        return 1;
    }
    uint8_t *bytes = malloc(byte_len);
    for (size_t i = 0; i < byte_len; i++) {
        bytes[i] = (hex_chars[2*i] << 4) | hex_chars[2*i+1];
    }

    size_t payload_len = byte_len - 4;
    uint32_t checksum = bytes[byte_len-4] | (bytes[byte_len-3] << 8) | (bytes[byte_len-2] << 16) | (bytes[byte_len-1] << 24);

    uint32_t hash = 0x12345678;
    for (size_t i = 0; i < payload_len; i++) {
        hash ^= bytes[i];
        hash = (hash << 5) | (hash >> 27);
        hash += 0x5A5A5A5A;
    }

    if (hash != checksum) {
        printf("ERR: INVALID CHECKSUM\n");
        return 1;
    }

    for (size_t i = 0; i < payload_len; i++) {
        putchar(bytes[i] ^ 0x42);
    }
    printf("\nVALID\n");
    return 0;
}
EOF

    gcc -O2 /tmp/oracle.c -o /app/token_validator
    strip /app/token_validator
    rm /tmp/oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
