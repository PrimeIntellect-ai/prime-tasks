#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/experiments

    cat << 'EOF' > /tmp/generate_data.py
import json
import random
import os

random.seed(42)

# Valid combinations
learning_rates = [0.001, 0.005, 0.01, 0.05, 0.1]
batch_sizes = [16, 32, 64, 128]
num_layers = [2, 3, 4, 5]

valid_runs = []
for i in range(40):
    run_id = f"run_valid_{i:03d}"
    lr = random.choice(learning_rates)
    bs = random.choice(batch_sizes)
    nl = random.choice(num_layers)
    # Generate some accuracy dependent on config to make the max predictable
    acc = 0.5 + (0.1 if bs == 64 else 0) + (0.1 if nl == 4 else 0) + random.uniform(0.01, 0.05)

    data = {
        "run_id": run_id,
        "learning_rate": lr,
        "batch_size": bs,
        "num_layers": nl,
        "metrics": {"val_accuracy": acc}
    }
    valid_runs.append(data)
    with open(f"/home/user/experiments/{run_id}.json", "w") as f:
        json.dump(data, f)

# Invalid runs
for i in range(10):
    run_id = f"run_invalid_{i:03d}"
    data = {
        "run_id": run_id,
        "learning_rate": random.choice(learning_rates),
        # Missing batch_size or wrong type
    }
    if i % 2 == 0:
        data["batch_size"] = str(random.choice(batch_sizes)) # string instead of int
        data["num_layers"] = random.choice(num_layers)
        data["metrics"] = {"val_accuracy": 0.8}
    else:
        data["batch_size"] = random.choice(batch_sizes)
        data["num_layers"] = random.choice(num_layers)
        data["metrics"] = {"val_accuracy": 0.8, "extra": 1} # extra key

    with open(f"/home/user/experiments/{run_id}.json", "w") as f:
        json.dump(data, f)

EOF
    python3 /tmp/generate_data.py

    chmod -R 777 /home/user
