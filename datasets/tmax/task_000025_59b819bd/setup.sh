#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Compile legacy_auth binary
    mkdir -p /app
    cat << 'EOF' > /app/legacy_auth.c
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv) {
    if (argc < 2) return 1;
    char *input = argv[1];
    for(int i = 0; i < strlen(input); i++) {
        printf("%02x", input[i] ^ 0x2A);
    }
    printf("\n");
    return 0;
}
EOF
    gcc -O2 -s /app/legacy_auth.c -o /app/legacy_auth
    rm /app/legacy_auth.c

    # Create dummy nginx config
    cat << 'EOF' > /home/user/nginx.conf.orig
server {
    listen 8000;
    location / {
        proxy_pass http://127.0.0.1:8080;
    }
}
EOF

    # Set permissions
    chmod -R 777 /home/user
