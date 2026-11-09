#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest pandas

    mkdir -p /app

    cat << 'EOF' > /tmp/qc.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    char line[1024];
    if (!fgets(line, sizeof(line), f)) { fclose(f); return 0; } // skip header
    while (fgets(line, sizeof(line), f)) {
        char *ts = strtok(line, ",");
        char *alpha = strtok(NULL, ",");
        char *beta = strtok(NULL, ",");
        char *gamma = strtok(NULL, "\n");
        if (beta && gamma) {
            double b = atof(beta);
            double g = atof(gamma);
            if (b * 2.0 < g) {
                fclose(f);
                return 1;
            }
        }
    }
    fclose(f);
    return 0;
}
EOF

    gcc -O2 -o /app/legacy_qc /tmp/qc.c
    strip -s /app/legacy_qc
    chmod +x /app/legacy_qc

    cat << 'EOF' > /tmp/generate_data.py
import os
import random
from datetime import datetime, timedelta

def generate_csv(path, is_evil):
    with open(path, 'w') as f:
        f.write("timestamp,sensor_alpha,sensor_beta,sensor_gamma\n")
        start_time = datetime(2023, 1, 1, 0, 0, 0)
        num_rows = random.randint(10, 50)
        evil_row = random.randint(0, num_rows - 1) if is_evil else -1

        for i in range(num_rows):
            ts = start_time + timedelta(minutes=i*random.randint(1, 10))
            alpha = random.uniform(0, 100)
            if is_evil and i == evil_row:
                beta = random.uniform(0, 10)
                gamma = beta * 2.0 + random.uniform(0.1, 10)
            else:
                beta = random.uniform(10, 50)
                gamma = beta * 2.0 - random.uniform(0.1, 10)
            f.write(f"{ts.isoformat()},{alpha:.2f},{beta:.2f},{gamma:.2f}\n")

os.makedirs('/home/user/data/clean', exist_ok=True)
os.makedirs('/home/user/data/evil', exist_ok=True)
os.makedirs('/home/user/samples', exist_ok=True)

for i in range(25):
    generate_csv(f'/home/user/data/clean/clean_{i}.csv', False)
    generate_csv(f'/home/user/data/evil/evil_{i}.csv', True)

for i in range(12):
    generate_csv(f'/home/user/samples/sample_clean_{i}.csv', False)
    generate_csv(f'/home/user/samples/sample_evil_{i}.csv', True)
EOF

    python3 /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
