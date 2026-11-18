#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    # Generate experiments data
    python3 -c '
import os
import json
import random
import numpy as np

os.makedirs("/home/user/experiments", exist_ok=True)
np.random.seed(42)

for i in range(1, 51):
    run_id = f"exp_{i:03d}"
    acc = np.clip(np.random.normal(0.75, 0.1), 0.1, 0.99)
    acc_var = np.random.uniform(0.001, 0.05)
    lat = np.random.normal(50, 15)
    mem = np.random.normal(250, 50)

    data = {
        "run_id": run_id,
        "accuracy": float(acc),
        "accuracy_variance": float(acc_var),
        "latency_ms": float(lat),
        "memory_mb": float(mem)
    }

    with open(f"/home/user/experiments/{run_id}.json", "w") as f:
        json.dump(data, f)
'

    chmod -R 777 /home/user
