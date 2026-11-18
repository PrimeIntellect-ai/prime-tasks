#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        binutils \
        file \
        nginx \
        strace \
        ltrace \
        gdb

    pip3 install pytest

    # Create the legacy alerter C source
    cat << 'EOF' > /tmp/legacy_alerter.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if(argc != 6) {
        return 1;
    }
    int cpu = atoi(argv[1]);
    int mem = atoi(argv[2]);
    int disk = atoi(argv[3]);
    int net = atoi(argv[4]);
    int err = atoi(argv[5]);

    // Hidden logic
    int score = cpu * 20 + mem * 15 + disk * 5 + net * 1 + err * 100;

    if (score > 5000 && err > 5) {
        printf("CRITICAL\n");
    } else if (score > 3000 || err > 10) {
        printf("WARNING\n");
    } else {
        printf("OK\n");
    }
    return 0;
}
EOF

    # Compile and strip the binary
    mkdir -p /app
    gcc -O2 /tmp/legacy_alerter.c -o /app/legacy_alerter
    strip /app/legacy_alerter

    # Create the user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
