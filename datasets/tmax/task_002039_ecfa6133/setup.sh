#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc inotify-tools binutils
    pip3 install pytest

    # Create the oracle binary
    mkdir -p /app
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdint.h>

int main() {
    uint32_t hash = 5381;
    int c;
    while ((c = getchar()) != EOF) {
        hash = hash * 37 + c;
    }
    printf("%08x\n", hash);
    return 0;
}
EOF
    gcc -O2 /app/oracle.c -o /app/manifest_hash_oracle
    strip /app/manifest_hash_oracle
    rm /app/oracle.c
    chmod +x /app/manifest_hash_oracle

    # Create user and project directory
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/project

    chmod -R 777 /home/user
