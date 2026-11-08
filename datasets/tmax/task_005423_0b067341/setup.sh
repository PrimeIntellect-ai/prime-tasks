#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make zlib1g-dev
    pip3 install pytest

    mkdir -p /app/doc-archiver-1.0

    cat << 'EOF' > /app/doc-archiver-1.0/main.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <zlib.h>

#define CHUNK 16384

int main() {
    char magic[4];
    if (fread(magic, 1, 4, stdin) != 4 || memcmp(magic, "DARC", 4) != 0) {
        return 1;
    }
    uint32_t size;
    if (fread(&size, 4, 1, stdin) != 1) return 1;

    z_stream strm;
    strm.zalloc = Z_NULL;
    strm.zfree = Z_NULL;
    strm.opaque = Z_NULL;
    if (inflateInit(&strm) != Z_OK) return 1;

    unsigned char in[CHUNK];
    unsigned char out[CHUNK];
    int ret;
    int state = 1; // 1 = line start, 0 = mid line, 2 = saw H, 3 = saw H1, 4 = saw H2

    do {
        strm.avail_in = fread(in, 1, CHUNK, stdin);
        if (ferror(stdin)) return 1;
        if (strm.avail_in == 0) break;
        strm.next_in = in;
        do {
            strm.avail_out = CHUNK;
            strm.next_out = out;
            ret = inflate(&strm, Z_NO_FLUSH);
            unsigned int have = CHUNK - strm.avail_out;
            for (unsigned int i = 0; i < have; i++) {
                char c = out[i];
                if (state == 1 && c == 'H') { state = 2; continue; }
                if (state == 2 && c == '1') { state = 3; continue; }
                if (state == 2 && c == '2') { state = 4; continue; }
                if (state == 3 && c == ':') { printf("# "); state = 0; continue; }
                if (state == 4 && c == ':') { printf("## "); state = 0; continue; }

                if (state == 2) { putchar('H'); state = 0; }
                else if (state == 3) { printf("H1"); state = 0; }
                else if (state == 4) { printf("H2"); state = 0; }

                putchar(c);
                if (c == '\n') state = 1;
            }
        } while (strm.avail_out == 0);
    } while (ret != Z_STREAM_END);

    if (state == 2) putchar('H');
    else if (state == 3) printf("H1");
    else if (state == 4) printf("H2");

    inflateEnd(&strm);
    return 0;
}
EOF

    cat << 'EOF' > /app/doc-archiver-1.0/Makefile
darc-extract: main.c
	gcc -O2 -o darc-extract main.c
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
