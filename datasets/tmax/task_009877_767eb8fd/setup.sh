#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    cat << 'EOF' > /tmp/setup_data.py
import os
import random
import math

os.makedirs('/home/user/data', exist_ok=True)
random.seed(42)

def generate_file(filename, is_baseline=False):
    with open(filename, 'w') as f:
        for r in range(1, 51): # 50 rows
            row_data = []
            for c in range(1, 101): # 100 cols
                # Base signal
                val = math.sin(r / 10.0) * math.cos(c / 10.0)
                if not is_baseline:
                    # Inject reduction noise. ROI is rows 10-40, cols 20-80.
                    # 31 * 61 = 1891 cells. 
                    # We want max difference to be around 0.08 so it triggers REJECT_NULL.
                    # We will randomly add noise between -0.0001 and 0.0002.
                    val += random.uniform(-0.0001, 0.0002)
                row_data.append(f"{val:.8f}")
            f.write(",".join(row_data) + "\n")

generate_file('/home/user/data/baseline.csv', is_baseline=True)
for i in range(1, 11):
    generate_file(f'/home/user/data/run_{i}.csv', is_baseline=False)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
