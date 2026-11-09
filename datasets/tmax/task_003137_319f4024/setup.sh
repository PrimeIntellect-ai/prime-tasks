#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc
    pip3 install pytest

    # Create suspicious repo
    mkdir -p /home/user/suspicious_repo
    cd /home/user/suspicious_repo
    git init
    git config user.email "hacker@evil.com"
    git config user.name "Hacker"
    echo "dummy" > dummy.txt
    git add dummy.txt
    git commit -m "Initial commit"

    echo "#define SECRET_MULTIPLIER 13.37" > config.h
    echo "Input: 42.0000 -> Int: 561" > trace.log
    git add config.h trace.log
    git commit -m "Add config and trace"

    git rm config.h trace.log
    git commit -m "Oops, delete sensitive files"
    git gc

    # Create malware encoder
    mkdir -p /app
    cat << 'EOF' > /tmp/encoder.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    float x;
    while (scanf("%f", &x) == 1) {
        int intermediate = (int)(x * 13.37f);
        float res = (float)intermediate / 13.37f;
        printf("%.6f\n", res);
    }
    return 0;
}
EOF
    gcc -O2 /tmp/encoder.c -o /app/malware_encoder
    strip /app/malware_encoder
    # Skipping UPX to avoid NotCompressibleException on small binaries

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
