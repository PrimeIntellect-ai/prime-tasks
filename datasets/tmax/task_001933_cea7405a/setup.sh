#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils curl tmux
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/legacy_calc.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char hex[256];
    if (fgets(hex, sizeof(hex), stdin) == NULL) return 1;
    hex[strcspn(hex, "\n")] = 0;

    char expr[128] = {0};
    int len = strlen(hex);
    for (int i = 0; i < len; i += 2) {
        char byte_str[3] = {hex[i], hex[i+1], 0};
        int byte = (int)strtol(byte_str, NULL, 16);
        expr[i/2] = (char)(byte ^ 0x5A);
    }

    int a, b;
    char op;
    if (sscanf(expr, "%d%c%d", &a, &op, &b) == 3) {
        if (op == '+') printf("%d\n", a + b);
        else if (op == '-') printf("%d\n", a - b);
        else if (op == '*') printf("%d\n", a * b);
    }
    return 0;
}
EOF

    gcc -O2 /app/legacy_calc.c -o /app/legacy_calc
    strip /app/legacy_calc
    rm /app/legacy_calc.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
