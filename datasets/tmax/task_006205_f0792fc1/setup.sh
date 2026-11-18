#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip strace
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/process_data.py
import numpy as np
import os
import json
import sys

def load_tolerance():
    config_path = '/home/user/.config/app_settings.json'
    if os.path.exists(config_path):
        try:
            with open(config_path, 'r') as f:
                data = json.load(f)
                return data.get('tolerance', 1e-12)
        except:
            return 1e-12
    return 1e-12

def process():
    tol = load_tolerance()
    val = np.int32(0)
    prev_metric = 0.0

    for i in range(1, 10000):
        # Bug: i^3 overflows int32 around i=1291
        term = np.int32(i) * np.int32(i) * np.int32(i)
        val += term

        # Simulated convergence metric: 1 / log(val + 2)
        # If val overflows to negative, this raises an error or oscillates
        if val <= 0:
            current_metric = 999.0 # Overflow penalty
        else:
            current_metric = 10000.0 / float(val)

        if abs(current_metric - prev_metric) < tol:
            print(f"Converged at iteration {i} to {current_metric:.8f}")
            sys.exit(0)

        prev_metric = current_metric

    print("Error: Convergence failed after 10000 iterations")
    sys.exit(1)

if __name__ == '__main__':
    process()
EOF

    chmod -R 777 /home/user
