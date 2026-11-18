#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import json
import numpy as np

base_dir = "/home/user/experiments"
os.makedirs(base_dir, exist_ok=True)

# Define 3 experiments
experiments = {
    "exp_alpha": {"seed": 42, "offset": 0.5},   # Will be positive
    "exp_beta": {"seed": 99, "offset": -2.0},   # Will be negative
    "exp_gamma": {"seed": 123, "offset": 1.5}   # Will be positive
}

input_dim = 4
hidden_dim = 8
output_dim = 1
num_samples = 50

for exp, config in experiments.items():
    exp_dir = os.path.join(base_dir, exp)
    os.makedirs(exp_dir, exist_ok=True)

    np.random.seed(config["seed"])

    # arch.json
    arch = {"input_dim": input_dim, "hidden_dim": hidden_dim, "output_dim": output_dim}
    with open(os.path.join(exp_dir, "architecture.json"), "w") as f:
        json.dump(arch, f)

    # features.csv
    X = np.random.randn(num_samples, input_dim)
    np.savetxt(os.path.join(exp_dir, "features.csv"), X, delimiter=",")

    # weights.npz
    W1 = np.random.randn(input_dim, hidden_dim)
    b1 = np.random.randn(hidden_dim)
    W2 = np.random.randn(hidden_dim, output_dim)
    b2 = np.random.randn(output_dim) + config["offset"]

    np.savez(os.path.join(exp_dir, "weights.npz"), W1=W1, b1=b1, W2=W2, b2=b2)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
