#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    mkdir -p /home/user/sim

    cat << 'EOF' > /home/user/sim/wave_sim.py
import numpy as np
import random
import sys

class SubDomain:
    def __init__(self, id, start, end):
        self.id = id
        self.x = np.linspace(start, end, 10000)

    def compute_val(self, t):
        # Generates a signal oscillating at exactly 7.0 Hz
        # Uses small values to exacerbate floating point round-off differences if order changes
        return np.sum(np.sin(2 * np.pi * 7.0 * t + self.x) * 1e-8)

def run_sim():
    num_blocks = 50
    blocks = {i: SubDomain(i, i, i+1) for i in range(num_blocks)}

    history = []
    # Simulation loop
    for step in range(250):
        t = step * 0.01  # dt = 0.01

        total = 0.0
        # The Bug: non-deterministic reduction order
        items = list(blocks.values())
        random.shuffle(items)

        for b in items:
            total += b.compute_val(t)

        history.append(total)

    np.save("/home/user/sim/energy.npy", history)
    print("Simulation complete. Saved to energy.npy")

if __name__ == "__main__":
    run_sim()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
