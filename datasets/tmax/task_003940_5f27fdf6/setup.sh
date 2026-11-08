#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/email_router.c
#include <stdio.h>
#include <string.h>

// DJB2 hash function modified for server routing
unsigned long hash_djb2(unsigned char *str) {
    unsigned long hash = 5381;
    int c;
    while ((c = *str++)) {
        hash = ((hash << 5) + hash) + c; /* hash * 33 + c */
    }
    return hash;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        return 1;
    }
    unsigned long h = hash_djb2((unsigned char *)argv[1]);
    int backend_id = h % 10;
    printf("%d\n", backend_id);
    return 0;
}
EOF

    gcc -O2 -s -o /app/email_router_bin /tmp/email_router.c
    chmod +x /app/email_router_bin
    rm /tmp/email_router.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
