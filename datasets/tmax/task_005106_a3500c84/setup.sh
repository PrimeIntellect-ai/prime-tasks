#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip valgrind socat netcat-openbsd gcc binutils libc6-dev
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/v1_calc.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    // Intentional memory leak: 1024 bytes definitely lost
    void *leak = malloc(1024);

    if (argc < 4) return 1;

    int a = atoi(argv[1]);
    int b = atoi(argv[2]);
    char op = argv[3][0];

    if (op == '/') {
        if (b == 0) {
            // Intentional segfault on div by zero
            int *crash = NULL;
            *crash = 1;
        }
        printf("%d\n", a / b);
    } else if (op == '+') {
        printf("%d\n", a + b);
    } else if (op == '-') {
        printf("%d\n", a - b);
    } else if (op == '*') {
        printf("%d\n", a * b);
    }

    return 0;
}
EOF

    gcc -O0 -o /app/v1_calc /tmp/v1_calc.c
    strip /app/v1_calc
    rm /tmp/v1_calc.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
