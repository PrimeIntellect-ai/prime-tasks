#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    # Create the oracle C source
    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 2;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 2;
    float x[64];
    if (fread(x, sizeof(float), 64, f) != 64) {
        fclose(f);
        return 2;
    }
    fclose(f);

    float sum = 0.0f;
    for (int i = 0; i < 64; i++) {
        if (i % 2 == 0) sum += 1.5f * x[i];
        else sum += -0.5f * x[i];
    }
    sum -= 10.0f;

    if (sum > 0.0f) return 1; // evil
    return 0; // clean
}
EOF

    gcc -O3 /tmp/oracle.c -o /app/anomaly_oracle
    strip -s /app/anomaly_oracle
    rm /tmp/oracle.c

    # Generate data
    cat << 'EOF' > /tmp/generate_data.py
import os
import struct
import random

evil_dir = "/var/opt/eval_data/evil"
clean_dir = "/var/opt/eval_data/clean"
os.makedirs(evil_dir, exist_ok=True)
os.makedirs(clean_dir, exist_ok=True)

for i in range(500):
    # generate evil
    x_evil = [random.uniform(-1.0, 1.0) for _ in range(64)]
    s = sum(1.5*x_evil[j] if j%2==0 else -0.5*x_evil[j] for j in range(64))
    diff = 10.001 - s
    x_evil[0] += diff / 1.5
    with open(f"{evil_dir}/evil_{i}.bin", "wb") as f:
        f.write(struct.pack('<64f', *x_evil))

    # generate clean
    x_clean = [random.uniform(-1.0, 1.0) for _ in range(64)]
    s = sum(1.5*x_clean[j] if j%2==0 else -0.5*x_clean[j] for j in range(64))
    diff = 9.999 - s
    x_clean[0] += diff / 1.5
    with open(f"{clean_dir}/clean_{i}.bin", "wb") as f:
        f.write(struct.pack('<64f', *x_clean))
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
