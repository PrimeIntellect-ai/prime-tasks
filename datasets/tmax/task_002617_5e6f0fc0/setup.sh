#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest numpy scipy pandas

    mkdir -p /app
    cat << 'EOF' > /app/parser.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    double row[10];
    while (fread(row, sizeof(double), 10, f) == 10) {
        printf("%f,%f,%f,%f,%f,%f,%f,%f,%f,%f\n",
            row[0], row[1], row[2], row[3], row[4],
            row[5], row[6], row[7], row[8], row[9]);
    }
    fclose(f);
    return 0;
}
EOF
    gcc -O2 /app/parser.c -o /app/legacy_parser
    strip /app/legacy_parser
    rm /app/parser.c

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import os

np.random.seed(42)
proj = np.random.randn(3, 10)

def gen_clean(path):
    data = np.random.randn(1000, 3) @ proj
    data.astype(np.float64).tofile(path)

def gen_evil(path):
    data = np.random.randn(1000, 10)
    data.astype(np.float64).tofile(path)

for d in ['/home/user/corpus/clean', '/verify/corpus/clean']:
    os.makedirs(d, exist_ok=True)
    for i in range(50):
        gen_clean(f"{d}/clean_{i}.bin")

for d in ['/home/user/corpus/evil', '/verify/corpus/evil']:
    os.makedirs(d, exist_ok=True)
    for i in range(50):
        gen_evil(f"{d}/evil_{i}.bin")
EOF
    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /verify || true
