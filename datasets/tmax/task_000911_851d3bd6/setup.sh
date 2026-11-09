#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest hypothesis

    mkdir -p /home/user/artifact_pipeline
    cd /home/user/artifact_pipeline

    cat << 'EOF' > fletcher_calc.c
#include <stdio.h>
#include <stdint.h>

int main() {
    uint16_t sum1 = 0;
    uint16_t sum2 = 0;
    int c;

    while ((c = getchar()) != EOF) {
        sum1 = (sum1 + (uint8_t)c) % 255;
        sum2 = (sum2 + sum1) % 255;
    }

    uint16_t checksum = (sum2 << 8) | sum1;
    printf("%04X\n", checksum);
    return 0;
}
EOF

    cat << 'EOF' > Makefile
CC=gcc
CFLAGS=-Wall -Werror

all: fletcher_calc

fletcher_calc: fletcher_calc.c
    $(CC) $(CFLAGS) fletcher_calc.c
EOF

    cat << 'EOF' > test_fletcher.py
import subprocess
import pytest
from hypothesis import given, settings
import hypothesis.strategies as st

def py_fletcher16(data: bytes) -> str:
    sum1 = 0
    sum2 = 0
    for byte in data:
        sum1 = (sum1 + byte) % 255
        sum2 = (sum2 + sum1) % 255
    checksum = (sum2 << 8) | sum1
    return f"{checksum:04X}"

# TODO: Implement the property-based test below
# The test should be named `test_c_binary_matches_python`
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
