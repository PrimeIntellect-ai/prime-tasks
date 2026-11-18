#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils strace ltrace xxd curl wget
    pip3 install pytest

    # Create the legacy_extractor fixture
    cat << 'EOF' > /tmp/extractor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char** argv) {
    if (argc != 2) return 1;
    FILE* f = fopen(argv[1], "rb");
    if (!f) return 1;
    char magic[4];
    fread(magic, 1, 4, f);
    if (memcmp(magic, "BKP\x01", 4) != 0) return 1;

    while(1) {
        unsigned char len;
        if (fread(&len, 1, 1, f) != 1) break;
        char fname[256] = {0};
        fread(fname, 1, len, f);
        unsigned int size;
        fread(&size, 4, 1, f);
        char* data = malloc(size);
        fread(data, 1, size, f);

        FILE* out = fopen(fname, "wb");
        if (out) {
            fwrite(data, 1, size, out);
            fclose(out);
        }
        free(data);
    }
    fclose(f);
    return 0;
}
EOF
    mkdir -p /app
    gcc -O2 /tmp/extractor.c -o /app/legacy_extractor
    strip /app/legacy_extractor
    rm /tmp/extractor.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
