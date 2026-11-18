#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/feature_extractor/src

    cat << 'EOF' > /home/user/data/network.json
{
  "0": [1, 2],
  "1": [0, 2, 3],
  "2": [0, 1],
  "3": [1]
}
EOF

    cat << 'EOF' > /home/user/data/generate_signals.py
import csv
import math
import random

random.seed(42)
with open('/home/user/data/signals.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['node_id', 'time', 'signal'])
    for node in range(4):
        freq = node + 2
        for t in range(128):
            signal = math.sin(2 * math.pi * freq * t / 128.0) + random.gauss(0, 0.5)
            writer.writerow([node, t, signal])
EOF

    python3 /home/user/data/generate_signals.py

    cd /home/user/feature_extractor
    cargo init --bin

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
