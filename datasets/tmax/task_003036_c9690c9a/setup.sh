#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        zlib1g-dev \
        espeak \
        rustc \
        cargo

    pip3 install pytest

    mkdir -p /app

    # Create the C source for the oracle
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <zlib.h>

int main() {
    size_t cap = 1024;
    size_t len = 0;
    uint8_t *buf = malloc(cap);
    if (!buf) return 1;
    int c;
    while ((c = getchar()) != EOF) {
        const char *rep = NULL;
        int rlen = 0;
        if (c == '&') { rep = "&amp;"; rlen = 5; }
        else if (c == '<') { rep = "&lt;"; rlen = 4; }
        else if (c == '>') { rep = "&gt;"; rlen = 4; }
        else if (c == '"') { rep = "&quot;"; rlen = 6; }
        else if (c == '\'') { rep = "&#x27;"; rlen = 6; }
        else {
            if (len + 1 > cap) { cap *= 2; buf = realloc(buf, cap); }
            buf[len++] = c;
            continue;
        }
        if (len + rlen > cap) { cap *= 2; buf = realloc(buf, cap); }
        memcpy(buf + len, rep, rlen);
        len += rlen;
    }

    const char *key = "rusty padlock";
    size_t key_len = strlen(key);
    for (size_t i = 0; i < len; i++) {
        buf[i] ^= key[i % key_len];
    }

    uint32_t c32 = crc32(0L, Z_NULL, 0);
    c32 = crc32(c32, buf, len);

    uint8_t header[4];
    header[0] = (c32 >> 24) & 0xFF;
    header[1] = (c32 >> 16) & 0xFF;
    header[2] = (c32 >> 8) & 0xFF;
    header[3] = c32 & 0xFF;

    fwrite(header, 1, 4, stdout);
    fwrite(buf, 1, len, stdout);
    free(buf);
    return 0;
}
EOF

    # Compile the oracle and strip it
    gcc -O2 /app/oracle.c -o /app/secure_logger_oracle -lz
    strip /app/secure_logger_oracle
    rm /app/oracle.c

    # Generate the audio file
    espeak -w /app/voicemail.wav "The encryption key is rusty padlock"

    # Create user
    useradd -m -s /bin/bash user || true

    # Ensure home directory is writable
    chmod -R 777 /home/user
