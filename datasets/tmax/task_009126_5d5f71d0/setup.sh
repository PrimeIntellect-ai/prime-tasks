#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk sed
    pip3 install pytest

    mkdir -p /home/user/traces
    mkdir -p /home/user/results

    # Generate synthetic trace data
    python3 -c '
import random
random.seed(42)
for i in range(1, 5):
    with open(f"/home/user/traces/trace_{i}.txt", "w") as f:
        for _ in range(50):
            val = random.expovariate(1.0 / (i * 1.5))
            f.write(f"{val:.4f}\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
