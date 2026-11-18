#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils strace ltrace bsdmainutils xxd
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/c2_decoder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    char *input = argv[1];
    int len = strlen(input);
    if (len % 2 != 0) return 1;

    int out_len = len / 2;
    unsigned char *decoded = malloc(out_len + 1);

    for (int i = 0; i < out_len; i++) {
        sscanf(&input[i*2], "%2hhx", &decoded[i]);
        decoded[i] ^= 0x4B;
    }

    // Reverse
    for (int i = 0; i < out_len / 2; i++) {
        unsigned char temp = decoded[i];
        decoded[i] = decoded[out_len - 1 - i];
        decoded[out_len - 1 - i] = temp;
    }

    decoded[out_len] = '\0';
    printf("%s\n", decoded);
    free(decoded);
    return 0;
}
EOF

    gcc -O2 -s /tmp/c2_decoder.c -o /app/c2_decoder
    rm /tmp/c2_decoder.c
    chmod 755 /app/c2_decoder

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
