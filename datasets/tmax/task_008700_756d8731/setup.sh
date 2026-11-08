#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/manifests

    cat << 'EOF' > /home/user/manifest_parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    char type[16];
    int size;
    // Bug 1: buffer too small, causing overflow. Bug 2: memory leak.
    while (fscanf(f, "%15s %d", type, &size) == 2) {
        char* leak = malloc(100);
        strcpy(leak, "leaked data");
        printf("ASSET: %s %d\n", type, size);
    }

    fclose(f);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/manifests/batch1.txt
TEXTURE 1024
AUDIO 512
TEXTURE 2048
EOF

    cat << 'EOF' > /home/user/manifests/batch2.txt
MODEL 4096
AUDIO 128
METADATA 64
EOF

    cat << 'EOF' > /home/user/manifests/batch3.txt
MODEL 1024
TEXTURE_HIGH_RESOLUTION_ASSET_NAME_OVER_SIXTEEN_CHARS 8192
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
