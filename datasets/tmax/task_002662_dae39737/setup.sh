#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make gawk bc
    pip3 install pytest

    mkdir -p /app/simkit-1.2
    cat << 'EOF' > /app/simkit-1.2/sim.c
#include <stdio.h>
#include <math.h>
#include <stdlib.h>

int main() {
    for(int i=0; i<10; i++) {
        printf("%f\n", sqrt((double)(rand() % 100)));
    }
    return 0;
}
EOF

    cat << 'EOF' > /app/simkit-1.2/Makefile
all:
	gcc -O2 -o sim sim.c
EOF

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    python3 -c "
import random
import os

random.seed(42)

for i in range(50):
    # Clean data: Normal distribution mean 10, std 1
    with open(f'/app/corpus/clean/data_{i}.txt', 'w') as f:
        for _ in range(100):
            f.write(f'{random.gauss(10, 1):.4f}\n')

    # Evil data: Normal distribution mean 10, std 5 (higher variance)
    with open(f'/app/corpus/evil/data_{i}.txt', 'w') as f:
        for _ in range(100):
            f.write(f'{random.gauss(10, 5):.4f}\n')
"

    # Ensure the app directory is writable so the agent can compile the executable
    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
