#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/certs
    cd /home/user/certs

    # 1. Generate Certificates
    openssl req -x509 -newkey rsa:2048 -days 365 -nodes -keyout ca.key -out ca.pem -subj "/CN=Fake Root CA" 2>/dev/null

    # Leaf A (Invalid - self-signed)
    openssl req -x509 -newkey rsa:2048 -days 365 -nodes -keyout leaf_A.key -out leaf_A.pem -subj "/CN=Leaf A" 2>/dev/null

    # Leaf B (Valid - signed by CA)
    openssl req -newkey rsa:2048 -nodes -keyout leaf_B.key -out leaf_B.csr -subj "/CN=Leaf B" 2>/dev/null
    openssl x509 -req -in leaf_B.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out leaf_B.pem -days 365 2>/dev/null

    # Leaf C (Invalid - wrong CA or self signed)
    openssl req -x509 -newkey rsa:2048 -days 365 -nodes -keyout leaf_C.key -out leaf_C.pem -subj "/CN=Leaf C" 2>/dev/null

    cd /home/user

    # 2. Create Security Log
    cat << 'EOF' > /home/user/security.log
[INFO] Connection established from IP 192.168.1.50
[WARN] Auth attempt using cert leaf_A.pem | Payload: aW52YWxpZF9wYXlsb2FkXzE=
[WARN] Auth attempt using cert leaf_B.pem | Payload: ZXhwbG9pdF90cmlnZ2VyXzk5
[WARN] Auth attempt using cert leaf_C.pem | Payload: YmVuaWduX2RhdGFfc3RyaW5n
EOF

    # 3. Create the Target Binary
    cat << 'EOF' > /home/user/target_source.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        return 1;
    }
    if (strcmp(argv[1], "exploit_trigger_99") == 0) {
        // Simulate a vulnerability causing a Segmentation Fault (SIGSEGV = 11)
        int *p = NULL;
        *p = 42; 
    }
    return 0;
}
EOF
    gcc /home/user/target_source.c -o /home/user/target_bin
    rm /home/user/target_source.c

    chmod -R 777 /home/user
