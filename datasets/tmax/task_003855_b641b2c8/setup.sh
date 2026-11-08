#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest requests

    mkdir -p /app

    cat << 'EOF' > /tmp/hasher.c
#include <stdio.h>
#include <stdlib.h>

unsigned long djb2_hash(unsigned char *str, size_t len) {
    unsigned long hash = 5381;
    for (size_t i = 0; i < len; i++) {
        hash = ((hash << 5) + hash) + str[i];
    }
    return hash;
}

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    fseek(f, 0, SEEK_END);
    long fsize = ftell(f);
    fseek(f, 0, SEEK_SET);

    unsigned char *string = malloc(fsize + 1);
    fread(string, fsize, 1, f);
    fclose(f);

    printf("CHASH-%lu", djb2_hash(string, fsize));
    free(string);
    return 0;
}
EOF

    gcc -O2 /tmp/hasher.c -o /app/config_hasher
    strip /app/config_hasher
    chmod +x /app/config_hasher

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
