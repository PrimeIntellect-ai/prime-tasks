#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    mkdir -p /home/user/auth_project/src/c_crypto
    mkdir -p /home/user/auth_project/lib

    cat << 'EOF' > /home/user/auth_project/src/c_crypto/crypto.c
#include <string.h>

void compute_hash(const char* input, char* output) {
    // In a real scenario, this would be a secure hash algorithm.
    // For testing, we do a static prefix.
    strcpy(output, "SECURE_");
    strcat(output, input);
}
EOF

    cat << 'EOF' > /home/user/auth_project/requirements.txt
Flask==2.0.0
Werkzeug==3.0.0
requests==2.31.0
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/auth_project
    chmod -R 777 /home/user
