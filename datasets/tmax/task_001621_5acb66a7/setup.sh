#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make sudo espeak
    pip3 install pytest

    mkdir -p /home/user/signal_project
    mkdir -p /app

    # Create project files
    cat << 'EOF' > /home/user/signal_project/poly_filter.h
#ifndef POLY_FILTER_H
#define POLY_FILTER_H

int apply_filter(int x);

#endif
EOF

    cat << 'EOF' > /home/user/signal_project/poly_filter.c
#include "poly_filter.h"
#include <math.h>

int apply_filter(int x) {
    // TODO: Insert coefficients from the audio memo
    long long c1 = 0; // TODO
    long long c2 = 0; // TODO
    long long c3 = 0; // TODO

    long long res = c1 * pow(x, 3) + c2 * pow(x, 2) + c3 * x;
    return (int)(res % 1000000007);
}
EOF

    cat << 'EOF' > /home/user/signal_project/main.c
#include <stdio.h>
#include <stdlib.h>
#include "poly_filter.h"

int main(int argc, char *argv[]) {
    if (argc < 2) {
        return 1;
    }
    int x = atoi(argv[1]);
    printf("%d\n", apply_filter(x));
    return 0;
}
EOF

    cat << 'EOF' > /home/user/signal_project/Makefile
CC=gcc
CFLAGS=-Wall

all: poly_tool

poly_tool: main.o
	$(CC) -o poly_tool main.o

main.o: main.c
	$(CC) $(CFLAGS) -c main.c

poly_filter.o: poly_filter.c
	$(CC) $(CFLAGS) -c poly_filter.c
EOF

    # Generate oracle binary
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        return 1;
    }
    int x = atoi(argv[1]);
    long long c1 = 42;
    long long c2 = 15;
    long long c3 = 99;
    long long res = c1 * pow(x, 3) + c2 * pow(x, 2) + c3 * x;
    printf("%d\n", (int)(res % 1000000007));
    return 0;
}
EOF
    gcc -O2 /app/oracle.c -o /app/oracle_bin -lm
    rm /app/oracle.c

    # Generate audio memo
    espeak -w /app/memo.wav "The calibration coefficients for the polynomial filter are forty two, fifteen, and ninety nine."

    # Create user and configure sudo
    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

    chmod -R 777 /home/user
    chmod -R 777 /app
