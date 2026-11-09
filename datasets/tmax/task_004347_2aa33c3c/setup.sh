#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make
pip3 install pytest

mkdir -p /app/bin
mkdir -p /app/calc_core-1.2.3/calc_core

# Create legacy_calc_ref C source and compile
cat << 'EOF' > /app/bin/legacy_calc_ref.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    char sig[4];
    if (fread(sig, 1, 4, f) != 4) return 1;
    if (strncmp(sig, "SENS", 4) != 0) return 1;
    unsigned int n;
    if (fread(&n, sizeof(unsigned int), 1, f) != 1) return 1;

    if (n == 0) {
        printf("0\n");
        return 0;
    }

    double *data = malloc(n * sizeof(double));
    if (fread(data, sizeof(double), n, f) != n) return 1;

    double mean = 0.0;
    double m2 = 0.0;
    for (unsigned int i = 0; i < n; i++) {
        double delta = data[i] - mean;
        mean += delta / (i + 1);
        double delta2 = data[i] - mean;
        m2 += delta * delta2;
    }
    double variance = m2 / n;
    printf("%.17g\n", variance);
    free(data);
    fclose(f);
    return 0;
}
EOF

gcc -O2 /app/bin/legacy_calc_ref.c -o /app/bin/legacy_calc_ref
rm /app/bin/legacy_calc_ref.c

# Create calc_core package
cat << 'EOF' > /app/calc_core-1.2.3/Makefile
test:
        python3 -m unittest discover
EOF

cat << 'EOF' > /app/calc_core-1.2.3/calc_core/__init__.py
EOF

cat << 'EOF' > /app/calc_core-1.2.3/calc_core/config.py
import os
LOG_DIR = os.environ["CALC_LOG_DIR"]
EOF

cat << 'EOF' > /app/calc_core-1.2.3/calc_core/parser.py
import struct

def parse(filename):
    with open(filename, "rb") as f:
        data = f.read()
    if data[:4] != b"SENS":
        raise ValueError("Invalid signature")
    length = struct.unpack("<I", data[4:8])[0]
    payload = data[8:8 + length*8]
    if length == 0:
        # Bug: fails if length == 0
        return struct.unpack("<d", payload)
    return struct.unpack(f"<{length}d", payload)
EOF

cat << 'EOF' > /app/calc_core-1.2.3/calc_core/math_ops.py
def calc_variance(data):
    if not data:
        return 0.0
    n = len(data)
    sum_x = sum(data)
    sum_x2 = sum(x**2 for x in data)
    return sum_x2 / n - (sum_x / n)**2
EOF

cat << 'EOF' > /app/calc_core-1.2.3/calc_core/cli.py
import sys
from . import config
from .parser import parse
from .math_ops import calc_variance

def main():
    if len(sys.argv) != 2:
        sys.exit(1)
    data = parse(sys.argv[1])
    var = calc_variance(data)
    print(f"{var:.17g}")

if __name__ == "__main__":
    main()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
