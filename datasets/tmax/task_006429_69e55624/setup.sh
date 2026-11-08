#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/generate_logs.py
import os
import random
import numpy as np

os.makedirs('/home/user', exist_ok=True)

random.seed(101)
np.random.seed(101)

with open('/home/user/integration_logs.txt', 'w') as f:
    for run_id in range(1, 51):
        num_steps = random.randint(3, 8)
        diverge = random.random() < 0.2  # 20% chance to diverge
        diverge_step = random.randint(1, num_steps) if diverge else -1

        current_error = random.uniform(0.001, 0.01)

        for step in range(1, num_steps + 1):
            if step == diverge_step:
                err_str = random.choice(["NaN", "Inf"])
                f.write(f"[RunID={run_id}] step={step*10} size=0.05 error={err_str}\n")
                break # Stops logging after divergence, simulating crash
            else:
                current_error += random.uniform(0.01, 0.05)
                f.write(f"[RunID={run_id}] step={step*10} size={random.choice(['0.01', '0.02', '0.05'])} error={current_error:.6f}\n")
EOF

    python3 /tmp/generate_logs.py
    rm /tmp/generate_logs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
