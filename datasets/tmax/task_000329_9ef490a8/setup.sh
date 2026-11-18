#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy

    # Create the legacy aggregator binary
    mkdir -p /app
    cat << 'EOF' > /app/legacy_aggregator.c
#include <stdio.h>
int main() {
    float sum = 0.0f;
    float val;
    while (scanf("%f", &val) == 1) {
        sum += val;
    }
    printf("%.6f\n", sum);
    return 0;
}
EOF
    gcc -O2 -s /app/legacy_aggregator.c -o /app/legacy_aggregator
    rm /app/legacy_aggregator.c

    # Generate log files
    mkdir -p /data
    cat << 'EOF' > /tmp/generate_logs.py
import os
import random

os.makedirs('/data', exist_ok=True)
with open('/data/gateway.log', 'w') as f1, open('/data/queue.log', 'w') as f2, open('/data/aggregator_node.log', 'w') as f3:
    tx_ids = ['TX-101', 'TX-102', 'TX-103']
    time = 1620000000.0
    for tx in tx_ids:
        vals = [10000000.0] + [0.011] * 10000
        random.shuffle(vals)
        for v in vals:
            time += 0.001
            target = random.choice([f1, f2, f3])
            target.write(f"{time:.3f} [{tx}] PAYLOAD_CHUNK: {v}\n")
EOF
    python3 /tmp/generate_logs.py
    rm /tmp/generate_logs.py

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
