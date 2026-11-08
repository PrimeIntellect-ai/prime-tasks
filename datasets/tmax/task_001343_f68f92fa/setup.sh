#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_logs.py
import os
import random
import numpy as np

random.seed(42)
np.random.seed(42)

def generate_logs(filename, mean, std, n_samples):
    with open(filename, 'w') as f:
        for i in range(n_samples):
            # Inject some noise
            if random.random() < 0.1:
                f.write(f"[2023-10-01 12:00:{random.randint(10,59)}] ERROR - Timeout occurred\n")
            elif random.random() < 0.05:
                f.write(f"[2023-10-01 12:00:{random.randint(10,59)}] WARNING - Inference time: NaN ms\n")

            # Valid sample
            latency = np.random.normal(mean, std)
            f.write(f"[2023-10-01 12:00:{random.randint(10,59)}] INFO - Inference time: {latency:.4f} ms\n")

generate_logs("/home/user/raw_logs_A.txt", 45.0, 5.0, 100)
generate_logs("/home/user/raw_logs_B.txt", 42.0, 6.0, 110)
EOF

    python3 /tmp/generate_logs.py
    rm /tmp/generate_logs.py

    chmod -R 777 /home/user
