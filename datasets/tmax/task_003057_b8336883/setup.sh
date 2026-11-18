#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app/data/clean /app/data/evil /app/test_data/clean /app/test_data/evil
    mkdir -p /home/user

    # Create the legacy C binary
    cat << 'EOF' > /tmp/legacy_stats.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    float val;
    float sum = 0.0f;
    float sum_sq = 0.0f;
    int n = 0;
    while (fscanf(f, "%f", &val) == 1) {
        sum += val;
        sum_sq += val * val;
        n++;
    }
    fclose(f);
    if (n == 0) return 0;
    float variance = (sum_sq - (sum * sum) / n) / n;
    printf("%f\n", variance);
    return 0;
}
EOF
    gcc -O2 -s -o /app/legacy_stats /tmp/legacy_stats.c
    rm /tmp/legacy_stats.c

    # Create dummy diagnostic script
    cat << 'EOF' > /app/run_diagnostics.py
#!/usr/bin/env python3
print("Diagnostic harness running...")
EOF
    chmod +x /app/run_diagnostics.py

    # Create requirements.txt with conflicts
    cat << 'EOF' > /home/user/requirements.txt
numpy==1.21.0
scipy>=1.8.0
pandas==1.3.5
EOF

    # Generate data
    cat << 'EOF' > /tmp/generate_data.py
import os
import random

def generate_files(path, is_evil, num_files=50):
    os.makedirs(path, exist_ok=True)
    for i in range(num_files):
        with open(os.path.join(path, f"data_{i}.txt"), "w") as f:
            if is_evil:
                base = 1000000.0
                for _ in range(100):
                    f.write(f"{base + random.uniform(-0.00001, 0.00001)}\n")
            else:
                base = 0.0
                for _ in range(100):
                    f.write(f"{base + random.uniform(-10.0, 10.0)}\n")

generate_files("/app/data/clean", False, 50)
generate_files("/app/data/evil", True, 50)
generate_files("/app/test_data/clean", False, 50)
generate_files("/app/test_data/evil", True, 50)
EOF
    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
