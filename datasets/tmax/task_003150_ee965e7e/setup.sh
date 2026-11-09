#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make golang-go
    pip3 install pytest

    mkdir -p /home/user/clib

    cat << 'EOF' > /home/user/clib/hwscore.h
#ifndef HWSCORE_H
#define HWSCORE_H
int get_hw_score(int seed);
#endif
EOF

    cat << 'EOF' > /home/user/clib/hwscore.c
#include "hwscore.h"
int get_hw_score(int seed) {
    int result = seed * 42;
    // Simple inline assembly: bitwise XOR with 0xAA
    __asm__("xor $0xAA, %0" : "+r" (result));
    return result;
}
EOF

    cat << 'EOF' > /home/user/clib/Makefile
all:
gcc -c hwscore.c -o hwscore.o
gcc hwscore.o -o libhwscore.so
EOF

    cat << 'EOF' > /home/user/rules.txt
5 3 + HW *
HW 10 - 2 /
15 HW +
100 2 / HW * 10 -
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
