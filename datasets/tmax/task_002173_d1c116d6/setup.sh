#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

mkdir -p /home/user/sim

# Create the naive C program
cat << 'EOF' > /home/user/sim/sum_potentials.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    float sum = 0.0f;
    float val;
    while (fscanf(f, "%f", &val) == 1) {
        sum += val;
    }
    fclose(f);
    printf("%.6f\n", sum);
    return 0;
}
EOF

# Generate data that causes precision loss in a naive float sum
python3 -c '
import random
vals = [10000000.0] + [0.05] * 200000
with open("/home/user/sim/data.txt", "w") as f:
    for v in vals:
        f.write(f"{v}\n")
'

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
