#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy scipy scikit-learn matplotlib

    mkdir -p /app/corpus/clean /app/corpus/evil /home/user

    # Create C source for legacy_filter
    cat << 'EOF' > /app/legacy_filter.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    double w[10] = {1.0, -1.0, 0.5, 0.5, -0.2, 0.2, 0.0, 0.0, 1.0, -1.0};
    double v[10];
    char *token = strtok(argv[1], ",");
    for (int i = 0; i < 10; i++) {
        if (!token) return 1;
        v[i] = atof(token);
        token = strtok(NULL, ",");
    }
    double dot = 0.0;
    for (int i = 0; i < 10; i++) dot += w[i] * v[i];
    if (fabs(dot) < 0.75) {
        printf("clean\n");
    } else {
        printf("evil\n");
    }
    return 0;
}
EOF

    gcc -O2 -s /app/legacy_filter.c -o /app/legacy_filter -lm
    rm /app/legacy_filter.c

    # Generate corpora
    cat << 'EOF' > /app/generate_corpus.py
import os
import numpy as np

w = np.array([1.0, -1.0, 0.5, 0.5, -0.2, 0.2, 0.0, 0.0, 1.0, -1.0])

os.makedirs('/app/corpus/clean', exist_ok=True)
os.makedirs('/app/corpus/evil', exist_ok=True)

def generate_clean():
    while True:
        v = np.random.randn(10)
        if abs(np.dot(w, v)) < 0.75:
            return v

def generate_evil():
    while True:
        v = np.random.randn(10)
        if abs(np.dot(w, v)) >= 0.75:
            return v

for i in range(50):
    clean_data = np.array([generate_clean() for _ in range(100)])
    np.savetxt(f'/app/corpus/clean/file_{i}.csv', clean_data, delimiter=',', fmt='%.6f')

    evil_data = [generate_clean() for _ in range(99)] + [generate_evil()]
    np.random.shuffle(evil_data)
    np.savetxt(f'/app/corpus/evil/file_{i}.csv', np.array(evil_data), delimiter=',', fmt='%.6f')
EOF

    python3 /app/generate_corpus.py
    rm /app/generate_corpus.py

    # Create plot_data.py
    cat << 'EOF' > /home/user/plot_data.py
import matplotlib.pyplot as plt
import numpy as np

# Missing matplotlib.use('Agg') causes failure in headless
data = np.random.rand(10, 2)
plt.scatter(data[:, 0], data[:, 1])
plt.title("Sample Plot")
plt.savefig('plot.png')
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
