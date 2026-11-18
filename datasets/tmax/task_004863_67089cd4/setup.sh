#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev binutils gdb ltrace strace
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/backup_decoder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    size_t capacity = 1024;
    size_t length = 0;
    unsigned char *buffer = malloc(capacity);
    if (!buffer) return 3;

    int c;
    while ((c = fgetc(stdin)) != EOF) {
        if (length >= capacity) {
            capacity *= 2;
            buffer = realloc(buffer, capacity);
            if (!buffer) return 3;
        }
        buffer[length++] = (unsigned char)c;
    }

    if (length < 4) {
        fprintf(stderr, "ERROR: Too short\n");
        return 1;
    }

    if (buffer[0] != 'B' || buffer[1] != 'K' || buffer[2] != 'P' || buffer[3] != '1') {
        fprintf(stderr, "ERROR: Invalid magic\n");
        return 2;
    }

    unsigned char key = 0x13;
    for (size_t i = 4; i < length; i++) {
        buffer[i] ^= key;
        key++;
    }

    fwrite(buffer + 4, 1, length - 4, stdout);
    free(buffer);
    return 0;
}
EOF

    gcc -static -O2 /tmp/backup_decoder.c -o /app/backup_decoder
    strip /app/backup_decoder
    rm /tmp/backup_decoder.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
