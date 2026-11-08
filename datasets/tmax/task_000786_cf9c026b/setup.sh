#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    # Create a dummy memory dump with embedded C code
    dd if=/dev/urandom of=/home/user/memory.dump bs=1M count=1 2>/dev/null

    cat << 'EOF' >> /home/user/memory.dump
// START_OF_RECOVERED_CODE
#include <stdio.h>

int main() {
    float sum = 1.0;
    float term = 1.0;
    int n = 1;

    while (fabs(term) > 1e-10) {
        term = term / n;
        sum += term;
        n++;
    }

    printf("%.9f\n", sum);
    return 0;
}
// END_OF_RECOVERED_CODE
EOF

    dd if=/dev/urandom bs=1M count=1 >> /home/user/memory.dump 2>/dev/null

    chown -R user:user /home/user
    chmod -R 777 /home/user
