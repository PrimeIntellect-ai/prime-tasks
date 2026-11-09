#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils
pip3 install pytest

mkdir -p /app/corpus/clean /app/corpus/evil

cat << 'EOF' > /tmp/gen_data.py
import struct
import os
import random

def write_floats(path, floats):
    with open(path, 'wb') as f:
        f.write(struct.pack(f'<{len(floats)}f', *floats))

# Clean corpus
for i in range(5):
    floats = [random.uniform(10.0, 100.0) for _ in range(100)]
    write_floats(f'/app/corpus/clean/clean_{i}.bin', floats)

# Evil corpus
# LR sum: (1e20 - 1e20) + 1.0 + 1.0 ... = 50.0
# RL sum: 50.0 - 1e20 + 1e20 = 0.0
# Diff = 50.0 > 0.01
for i in range(5):
    floats = [1e20, -1e20] + [1.0] * 50
    write_floats(f'/app/corpus/evil/evil_{i}.bin', floats)
EOF

python3 /tmp/gen_data.py

cat << 'EOF' > /tmp/aligner.c
#include <stdio.h>
int main() {
    printf("Dummy aligner\n");
    return 0;
}
EOF
gcc /tmp/aligner.c -o /app/signal_aligner
strip -s /app/signal_aligner

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
