#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-numpy cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import random
import numpy as np

random.seed(42)
np.random.seed(42)

algo_a_times = np.random.normal(1500, 100, 30)
algo_b_times = np.random.normal(1430, 90, 30)

bases = ['A', 'C', 'G', 'T']

with open("/home/user/raw_profiling.txt", "w") as f:
    for i in range(30):
        # Algo A
        target_a = "".join(random.choices(bases, k=20))
        primer_a = "".join(random.choices(bases, k=10))
        time_a = int(algo_a_times[i])
        f.write(f"run_A_{i}|AlgoA|{target_a}|{primer_a}|{time_a}\n")

        # Algo B
        target_b = "".join(random.choices(bases, k=20))
        primer_b = "".join(random.choices(bases, k=10))
        time_b = int(algo_b_times[i])
        f.write(f"run_B_{i}|AlgoB|{target_b}|{primer_b}|{time_b}\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
