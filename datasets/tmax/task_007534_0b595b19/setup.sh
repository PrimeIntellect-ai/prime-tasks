#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/math_project/src
    mkdir -p /home/user/math_project/include

    cat << 'EOF' > /home/user/math_project/Makefile
CC=gcc
CFLAGS=-I./include

all:
	$(CC) $(CFLAGS) src/main.c src/math_ops.c -o math_app
EOF

    cat << 'EOF' > /home/user/math_project/include/math_ops.h
#ifndef MATH_OPS_H
#define MATH_OPS_H

long long gcd(long long a, long long b);
long long compute_lcm(long long a, long long b);
double dummy_power(double base, double exp);

#endif
EOF

    cat << 'EOF' > /home/user/math_project/src/math_ops.c
#include "math_ops.h"
#include <math.h>

long long gcd(long long a, long long b) {
    while (b != 0) {
        long long temp = b;
        b = a % b;
        a = temp;
    }
    return a;
}

long long compute_lcm(long long a, long long b) {
    // BUG: a * b can overflow before division
    return (a * b) / gcd(a, b);
}

double dummy_power(double base, double exp) {
    return pow(base, exp);
}
EOF

    cat << 'EOF' > /home/user/math_project/src/main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "math_ops.h"

int main(int argc, char **argv) {
    if (argc < 3) {
        printf("Usage: %s <input_file> <output_file>\n", argv[0]);
        return 1;
    }

    FILE *in = fopen(argv[1], "r");
    if (!in) return 1;

    FILE *out = fopen(argv[2], "w");
    if (!out) {
        fclose(in);
        return 1;
    }

    char op[16];
    long long a, b;
    while (fscanf(in, "%15s %lld %lld", op, &a, &b) == 3) {
        if (strcmp(op, "LCM") == 0) {
            fprintf(out, "%lld\n", compute_lcm(a, b));
        }
    }

    fclose(in);
    fclose(out);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/math_project/queries.txt
LCM 15 20
LCM 1000000 2000000
LCM 123456 654321
LCM 3000000000 4000000000
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
