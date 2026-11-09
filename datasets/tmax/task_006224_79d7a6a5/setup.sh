#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate_data.py
import math
import random

random.seed(123)
with open("/home/user/spectroscopy_data.csv", "w") as f:
    C = 1.0
    k = 0.1
    M = 100.0
    for t in range(100):
        # Generate theoretical C(t) using exact analytical solution for realism, 
        # but add noise for the simulation.
        # analytical: C(t) = M / (1 + ((M - C0)/C0) * exp(-k*t))
        exact = M / (1 + ((M - 1.0)/1.0) * math.exp(-k * t))
        noise = random.uniform(-5.0, 5.0)
        noisy_val = max(0.0, exact + noise)
        f.write(f"{t},{noisy_val:.4f}\n")
EOF

    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    chmod -R 777 /home/user
