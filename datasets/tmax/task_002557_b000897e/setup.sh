#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user

    python3 -c "
import random
random.seed(42)
with open('/home/user/firmware.bin', 'wb') as f:
    f.write(bytes([random.randint(0, 255) for _ in range(10240)]))
"

    cat << 'EOF' > /home/user/calc_hash.py
#!/usr/bin/env python3
import sys

def parse_expr(expr):
    # Evaluates A*B+C
    if '*' in expr and '+' in expr:
        parts1 = expr.split('+')
        c = int(parts1[1])
        parts2 = parts1[0].split('*')
        a = int(parts2[0])
        b = int(parts2[1])
        return a * b + c
    return int(expr)

def calc_checksum(filepath, size):
    with open(filepath, 'rb') as f:
        data = f.read(size)
    checksum = 0
    for byte in data:
        # 8-bit circular left shift and XOR
        checksum = (((checksum << 1) | (checksum >> 7)) & 0xFF)
        checksum ^= byte
    return checksum

if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(1)
    size = parse_expr(sys.argv[2])
    print(calc_checksum(sys.argv[1], size))
EOF
    chmod +x /home/user/calc_hash.py

    cat << 'EOF' > /home/user/calc_hash.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int parse_expr(char *expr) {
    int a, b, c;
    // BUG: hardcoded offsets and potentially uninitialized variables
    char *plus = strchr(expr, '+');
    char *star = strchr(expr, '*');
    if (star && plus) {
        *star = '\0';
        *plus = '\0';
        a = atoi(expr);
        b = atoi(star + 1);
        c = atoi(plus + 1);
        return a * b + c;
    }
    return atoi(expr);
}

int main(int argc, char **argv) {
    if (argc != 3) return 1;

    char expr_copy[10]; // BUG: Buffer overflow
    strcpy(expr_copy, argv[2]); 

    int size = parse_expr(expr_copy);

    FILE *f = fopen(argv[1], "rb");
    // BUG: no check if f == NULL

    char *data = malloc(size);
    fread(data, 1, size, f); // BUG: doesn't check bytes read

    char checksum = 0; // BUG: signed char, causes undefined behavior/incorrect shifting
    for (int i = 0; i < size; i++) {
        // BUG: UB on signed bitwise operations
        checksum = ((checksum << 1) | (checksum >> 7));
        checksum ^= data[i];
    }

    printf("%d\n", checksum & 0xFF);
    // BUG: resource leak (fclose, free)
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
