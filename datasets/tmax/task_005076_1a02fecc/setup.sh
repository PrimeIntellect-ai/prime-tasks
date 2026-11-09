#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest websockets hypothesis

    useradd -m -s /bin/bash user || true

    mkdir -p /app

    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

static int b64_char_value(char c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return -1;
}

size_t b64_decode(const char *in, unsigned char *out) {
    size_t in_len = strlen(in);
    size_t out_len = 0;
    int val = 0, valb = -8;
    for (size_t i = 0; i < in_len; i++) {
        int c = b64_char_value(in[i]);
        if (c == -1) break;
        val = (val << 6) + c;
        valb += 6;
        if (valb >= 0) {
            out[out_len++] = (val >> valb) & 0xFF;
            valb -= 8;
        }
    }
    return out_len;
}

uint32_t crc32(const unsigned char *s, size_t n) {
    uint32_t crc = 0xFFFFFFFF;
    for (size_t i = 0; i < n; i++) {
        crc ^= s[i];
        for (int j = 0; j < 8; j++)
            crc = (crc >> 1) ^ (0xEDB88320 & (-(crc & 1)));
    }
    return ~crc;
}

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    size_t len = strlen(argv[1]);
    unsigned char *out = malloc(len);
    size_t out_len = b64_decode(argv[1], out);
    uint32_t crc = crc32(out, out_len);
    uint32_t final = crc ^ 0xDEADBEEF;
    printf("%08x\n", final);
    free(out);
    return 0;
}
EOF

    gcc -O2 /tmp/oracle.c -o /app/telemetry_oracle
    strip /app/telemetry_oracle
    rm /tmp/oracle.c

    cat << 'EOF' > /home/user/legacy_checksum.js
// /home/user/legacy_checksum.js
// Base CRC32 implementation
function makeCRCTable() {
    var c;
    var crcTable = [];
    for(var n =0; n < 256; n++){
        c = n;
        for(var k =0; k < 8; k++){
            c = ((c&1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1));
        }
        crcTable[n] = c;
    }
    return crcTable;
}

function get_base_checksum(str) {
    var crcTable = window.crcTable || (window.crcTable = makeCRCTable());
    var crc = 0 ^ (-1);
    for (var i = 0; i < str.length; i++ ) {
        crc = (crc >>> 8) ^ crcTable[(crc ^ str.charCodeAt(i)) & 0xFF];
    }
    return (crc ^ (-1)) >>> 0;
}
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
