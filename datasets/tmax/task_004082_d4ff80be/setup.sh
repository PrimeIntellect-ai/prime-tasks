#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc bc gawk
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/solve_ode.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    FILE* f = fopen(argv[1], "r");
    if (!f) return 1;
    double alpha=0, beta=0, gamma=0;
    char line[256];
    while(fgets(line, sizeof(line), f)) {
        sscanf(line, "alpha=%lf", &alpha);
        sscanf(line, "beta=%lf", &beta);
        sscanf(line, "gamma=%lf", &gamma);
    }
    fclose(f);

    if (alpha < 0) {
        int volatile x = 0;
        int y = 1 / x; // FPE
        return y;
    }
    if (alpha * beta <= gamma) {
        char *ptr = NULL;
        *ptr = 1; // Segfault
    }

    printf("Success: ODE solved.\n");
    return 0;
}
EOF

    gcc -O2 -s /app/solve_ode.c -o /app/solve_ode
    rm /app/solve_ode.c

    mkdir -p /truth/clean_corpus
    mkdir -p /truth/evil_corpus

    cat << 'EOF' > /tmp/gen_corpus.py
import os
import random

os.makedirs('/truth/clean_corpus', exist_ok=True)
os.makedirs('/truth/evil_corpus', exist_ok=True)

# Clean: alpha >= 0 and alpha * beta > gamma
for i in range(50):
    alpha = random.uniform(0.1, 10.0)
    beta = random.uniform(0.1, 10.0)
    gamma = random.uniform(-10.0, alpha * beta - 0.1)
    with open(f'/truth/clean_corpus/file_{i}.txt', 'w') as f:
        f.write(f"alpha={alpha}\nbeta={beta}\ngamma={gamma}\n")

# Evil: alpha < 0 OR alpha * beta <= gamma
for i in range(50):
    if random.choice([True, False]):
        alpha = random.uniform(-10.0, -0.1)
        beta = random.uniform(0.1, 10.0)
        gamma = random.uniform(0.1, 10.0)
    else:
        alpha = random.uniform(0.1, 10.0)
        beta = random.uniform(0.1, 10.0)
        gamma = random.uniform(alpha * beta + 0.1, alpha * beta + 10.0)
    with open(f'/truth/evil_corpus/file_{i}.txt', 'w') as f:
        f.write(f"alpha={alpha}\nbeta={beta}\ngamma={gamma}\n")
EOF

    python3 /tmp/gen_corpus.py
    rm /tmp/gen_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
