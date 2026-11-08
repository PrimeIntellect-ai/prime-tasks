#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/api_parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc < 2) {
        printf("Usage: %s <file>\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    unsigned char len;
    if (fread(&len, 1, 1, f) != 1) {
        fclose(f);
        return 1;
    }

    char buffer[50];
    // VULNERABILITY: No bounds checking on len
    if (fread(buffer, 1, len, f) != len) {
        fclose(f);
        return 1;
    }

    buffer[len] = '\0'; // OUT OF BOUNDS WRITE IF len >= 50
    printf("Successfully parsed REST payload of length: %d\n", len);

    fclose(f);
    return 0;
}
EOF

    chmod -R 777 /home/user
