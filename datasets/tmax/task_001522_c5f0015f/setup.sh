#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make xxd
    pip3 install pytest

    mkdir -p /home/user/waf_encoder

    cat << 'EOF' > /home/user/waf_encoder/encoder.c
#include <stdio.h>
#include <string.h>
// BUG: missing stdlib.h for malloc and free, causes warning/error with -Werror

int main() {
    int size;
    if (scanf("%d:", &size) != 1) return 1;
    char *buf = malloc(size + 1);
    if (!buf) return 1;
    fread(buf, 1, size, stdin);
    for(int i=0; i<size; i++) {
        printf("%02x", (unsigned char)buf[i]);
    }
    printf("\n");
    free(buf);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/waf_encoder/Makefile
CC=gcc
CFLAGS=-Wall -Werror

encoder: encoder.c
    $(CC) $(CFLAGS) -o encoder encoder.c
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
