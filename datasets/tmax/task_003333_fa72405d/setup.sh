#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/build_env
    cd /home/user/build_env

    cat << 'EOF' > algo.c
#include <stdio.h>

long long collatz_length(long long n) {
    long long steps = 0;
    while (n > 1) {
        if (n % 2 == 0) {
            n = n / 2;
        } else {
            n = 3 * n + 1;
        }
        steps++;
    }
    return steps;
}

int main() {
    printf("Collatz length for 10 is %lld\n", collatz_length(10));
    return 0;
}
EOF

    printf "all:\n\tgcc -o colltz missing.c\n" > Makefile

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
