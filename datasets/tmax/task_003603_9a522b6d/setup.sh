#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/results

    cat << 'EOF' > /tmp/generate_data.py
import os
import json
import numpy as np

os.makedirs('/home/user/data', exist_ok=True)
os.makedirs('/home/user/results', exist_ok=True)

np.random.seed(42)
genes = {
    "PER1": {"A": 10.0, "T": 24.1, "phi": 1.0, "B": 20.0},
    "BMAL1": {"A": 15.0, "T": 23.8, "phi": 4.0, "B": 30.0},
    "CLOCK": {"A": 5.0, "T": 24.5, "phi": 2.5, "B": 15.0}
}

times = np.arange(0, 72, 2) # 36 time points, 0 to 70 hours

records = []
for g, p in genes.items():
    for t in times:
        val = p["A"] * np.cos(2 * np.pi * t / p["T"] + p["phi"]) + p["B"]
        val += np.random.normal(0, 0.5)
        records.append({"gene_id": g, "time_hours": float(t), "expression_level": round(float(val), 4)})

np.random.shuffle(records)

with open("/home/user/data/raw_expression.json", "w") as f:
    json.dump(records, f, indent=2)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
