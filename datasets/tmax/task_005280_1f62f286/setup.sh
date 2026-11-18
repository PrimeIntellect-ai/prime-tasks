#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/payload_gen.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    char *input = argv[1];
    int len = strlen(input);
    if (len != 64) return 1;

    for (int i = 0; i < len; i += 2) {
        char buf[3] = {input[i], input[i+1], 0};
        unsigned int b;
        sscanf(buf, "%x", &b);
        b ^= 0x42;
        b = (b + 0x17) & 0xFF;
        printf("%02x", b);
    }
    printf("\n");
    return 0;
}
EOF

    gcc -O2 /tmp/payload_gen.c -o /app/payload_gen
    strip /app/payload_gen
    chmod +x /app/payload_gen
    rm /tmp/payload_gen.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
