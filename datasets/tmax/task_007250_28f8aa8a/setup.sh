#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc openssl binutils
    pip3 install pytest cryptography

    mkdir -p /home/user
    cd /home/user

    # Generate a specific certificate for the setup
    openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Organization/CN=c2.malicious-domain.local" 2>/dev/null

    # Properly embed the real cert into the C code
    CERT_CONTENT=$(cat cert.pem | sed 's/\\/\\\\/g; s/"/\\"/g; s/^/"/; s/$/\\n"/')
    cat << EOF > source.c
#include <stdio.h>

const char* embedded_cert = 
$CERT_CONTENT;

int main() {
    printf("Worker Process Initialized.\n");
    return 0;
}
EOF

    # Compile the binary
    gcc -o suspicious_binary source.c
    rm source.c key.pem cert.pem

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
