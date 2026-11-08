#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_log.py
import numpy as np

np.random.seed(99)
# Create a mix of large and small numbers to induce float16 addition variance
large_vals = np.random.uniform(100, 1000, 50)
small_vals = np.random.uniform(0.001, 0.1, 950)
all_vals = np.concatenate([large_vals, small_vals])
np.random.shuffle(all_vals)

with open("/home/user/app_profile.log", "w") as f:
    for i, val in enumerate(all_vals):
        f.write(f"[2023-10-12 10:00:01] INFO Thread-{i%8}: partial_metric = {val}\n")
    # Add some noise lines
    f.write("[2023-10-12 10:00:02] INFO Thread-0: connection closed\n")
    f.write("[2023-10-12 10:00:02] WARN Thread-1: retrying connection\n")
EOF

    python3 /tmp/generate_log.py
    rm /tmp/generate_log.py

    chmod -R 777 /home/user
