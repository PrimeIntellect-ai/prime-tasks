#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Generate self-signed cert
    openssl req -x509 -newkey rsa:2048 -keyout /home/user/server.key -out /home/user/server.crt -days 365 -nodes -subj "/CN=localhost"

    # Create headers.log
    cat << 'EOF' > /home/user/headers.log
HTTP/1.1 200 OK
Date: Wed, 21 Oct 2023 07:28:00 GMT
Server: Apache/2.4.41 (Ubuntu)
Strict-Transport-Security: max-age=31536000; includeSubDomains
Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-eval' https://scripts.example.com; object-src 'none';
Content-Type: text/html; charset=UTF-8
EOF

    # Create weak_hash.c
    cat << 'EOF' > /home/user/weak_hash.c
#include <stdint.h>
#include <string.h>

uint16_t weak_hash(const char* input) {
    uint16_t hash = 0x5555;
    for(int i = 0; i < strlen(input); i++) {
        hash = (hash << 5) + hash + input[i];
    }
    return hash;
}
EOF

    chmod -R 777 /home/user
