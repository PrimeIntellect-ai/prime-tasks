#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas pyarrow
    pip3 install torch --index-url https://download.pytorch.org/whl/cpu

    mkdir -p /home/user/experiment_data/raw
    mkdir -p /home/user/experiment_data/model

    cat << 'EOF' > /home/user/experiment_data/setup_env.py
import numpy as np
import json
import os

np.random.seed(42)

# Generate 50 CSV files
raw_dir = "/home/user/experiment_data/raw"
os.makedirs(raw_dir, exist_ok=True)

for i in range(50):
    data = np.random.randn(10000, 20)
    # Add some structure so correlations aren't all exactly 0
    data[:, 0] += i * 0.01 
    data[:, 5] -= data[:, 2] * 0.5
    np.savetxt(os.path.join(raw_dir, f"sim_{i}.csv"), data, delimiter=",")

# Generate Model Weights
hidden_weight = np.random.randn(32, 20) / np.sqrt(20)
hidden_bias = np.random.randn(32)
output_weight = np.random.randn(1, 32) / np.sqrt(32)
output_bias = np.random.randn(1)

model_dict = {
    "hidden.weight": hidden_weight.tolist(),
    "hidden.bias": hidden_bias.tolist(),
    "output.weight": output_weight.tolist(),
    "output.bias": output_bias.tolist()
}

os.makedirs("/home/user/experiment_data/model", exist_ok=True)
with open("/home/user/experiment_data/model/architecture_and_weights.json", "w") as f:
    json.dump(model_dict, f)
EOF
    python3 /home/user/experiment_data/setup_env.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
