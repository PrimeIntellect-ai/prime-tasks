#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy

    mkdir -p /app/bin /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /tmp/spec_deconv.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        // Read from stdin if no file provided, but task says it takes file path
        // Actually task says: "takes a time-domain signal ... as input"
        return 1;
    }
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    float vals[10000];
    int n = 0;
    while (fscanf(f, "%f", &vals[n]) == 1 && n < 10000) {
        n++;
    }
    fclose(f);

    for (int i = 0; i <= n - 10; i++) {
        float sum = 0;
        for (int j = 0; j < 10; j++) sum += vals[i+j];
        float mean = sum / 10;
        float var = 0;
        for (int j = 0; j < 10; j++) var += (vals[i+j] - mean) * (vals[i+j] - mean);
        var /= 10;
        if (var > 50.0) {
            while(1) {} // Diverge (infinite loop)
        }
    }
    printf("Deconvolution successful\n");
    return 0;
}
EOF

    gcc -O2 /tmp/spec_deconv.c -o /app/bin/spec_deconv
    strip /app/bin/spec_deconv

    cat << 'EOF' > /tmp/gen_data.py
import os
import random

random.seed(42)

for i in range(5):
    with open(f'/app/corpus/clean/signal_{i}.txt', 'w') as f:
        for _ in range(100):
            f.write(f"{random.uniform(0, 5)}\n")

for i in range(5):
    with open(f'/app/corpus/evil/signal_{i}.txt', 'w') as f:
        for _ in range(45):
            f.write(f"{random.uniform(0, 5)}\n")
        # Insert high variance window
        for _ in range(10):
            f.write(f"{random.uniform(0, 100)}\n")
        for _ in range(45):
            f.write(f"{random.uniform(0, 5)}\n")
EOF

    python3 /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 755 /app
