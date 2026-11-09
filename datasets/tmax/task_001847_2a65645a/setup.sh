#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc zlib1g-dev binutils gdb
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/renamer.c
#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include <stdlib.h>
#include <zlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        return 1;
    }
    char *input = argv[1];
    unsigned long crc = crc32(0L, Z_NULL, 0);
    crc = crc32(crc, (const unsigned char*)input, strlen(input));

    char modified[4096];
    strncpy(modified, input, sizeof(modified)-1);
    modified[sizeof(modified)-1] = '\0';

    for(int i=0; modified[i]; i++) {
        modified[i] = tolower((unsigned char)modified[i]);
        if(modified[i] == ' ') {
            modified[i] = '_';
        }
    }

    char *dot = strchr(modified, '.');
    if (dot) {
        *dot = '\0';
        printf("%s_%08lx.%s\n", modified, crc, dot + 1);
    } else {
        printf("%s_%08lx\n", modified, crc);
    }
    return 0;
}
EOF

    gcc -O2 /tmp/renamer.c -o /app/renamer_utility -lz
    strip /app/renamer_utility
    chmod +x /app/renamer_utility
    rm /tmp/renamer.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
