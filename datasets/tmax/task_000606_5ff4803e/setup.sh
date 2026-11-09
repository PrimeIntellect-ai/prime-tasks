#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq bc gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/sim_logs

    cat << 'EOF' > /home/user/setup_logs.py
import os
import random

random.seed(42)

def generate_log(filename, diverge=False):
    with open(filename, 'w') as f:
        step_size = 0.1
        for i in range(100):
            error = random.uniform(0.001, 0.01)
            f.write(f"{i} {step_size:.6f} {error:.6f}\n")

            # Next step size logic
            if error > 0.005:
                if diverge and random.random() < 0.3:
                    # Diverge: do not reduce enough
                    step_size = step_size * 0.8
                else:
                    # Correct: reduce by half or more
                    step_size = step_size * 0.4
            else:
                # Increase slightly
                step_size = step_size * 1.1

for i in range(1, 6):
    node_name = f"node_{i:02d}"
    diverge = (i in [2, 4]) # nodes 2 and 4 will have violations
    generate_log(f"/home/user/sim_logs/{node_name}.log", diverge)
EOF

    python3 /home/user/setup_logs.py
    rm /home/user/setup_logs.py

    chmod -R 777 /home/user
