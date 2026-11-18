#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas pyarrow fastparquet

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > generate_data.py
import json
import csv
import random

random.seed(42)
experiments = [f"EXP_{i:03d}" for i in range(1, 21)]

# 1. jsonl
with open("experiments.jsonl", "w") as f:
    for exp in experiments:
        data = {
            "experiment_id": exp,
            "learning_rate": round(random.uniform(0.0001, 0.1), 5),
            "batch_size": random.choice([16, 32, 64, 128])
        }
        f.write(json.dumps(data) + "\n")

# 2. csv (misses EXP_005 and EXP_015 to test inner join)
with open("metrics.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["experiment_id", "final_loss", "final_accuracy"])
    for exp in experiments:
        if exp in ["EXP_005", "EXP_015"]:
            continue
        loss = round(random.uniform(0.1, 1.5), 4)
        acc = round(random.uniform(0.7, 0.99), 4)
        writer.writerow([exp, loss, acc])

# 3. logs
log_messages = [
    "INFO: Starting run...",
    "WARNING: High memory usage detected.",
    "ERROR: NaN loss encountered. retrying...",
    "INFO: Checkpoint saved.",
    "WARNING: GPU utilization is low. Warning!",
    "ERROR: Connection timeout. Error! error!",
    "INFO: Run completed successfully."
]

with open("logs.txt", "w") as f:
    for exp in experiments:
        num_logs = random.randint(1, 5)
        for _ in range(num_logs):
            msg = random.choice(log_messages)
            f.write(f"[exp_id: {exp}] {msg}\n")
EOF

    python3 generate_data.py
    rm generate_data.py

    chmod -R 777 /home/user
