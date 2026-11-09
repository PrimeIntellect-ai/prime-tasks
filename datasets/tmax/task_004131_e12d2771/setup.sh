#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb strace socat netcat bc
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/legacy_calc.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    int x;
    setvbuf(stdout, NULL, _IONBF, 0);
    while (scanf("%d", &x) == 1) {
        // The intentional bug: Division by zero if x is a multiple of 7
        int dummy = 100 / (x % 7);

        // The math algorithm: Euler's prime generating polynomial modulo 1000
        int result = (x * x + x + 41) % 1000;
        printf("%d\n", result);
    }
    return 0;
}
EOF

    gcc -O2 -s /tmp/legacy_calc.c -o /app/legacy_calc
    chmod +x /app/legacy_calc

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
