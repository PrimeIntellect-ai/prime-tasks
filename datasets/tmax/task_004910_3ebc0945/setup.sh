#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    python3 -c '
import random
import csv

random.seed(42)
with open("/home/user/data/benchmarks.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["model_id", "inference_time_ms", "accuracy", "cpu_utilization"])
    for i in range(1, 1001):
        # Generate some correlated data
        base = random.uniform(10, 100)
        inference_time = base + random.uniform(-10, 10)
        # negative correlation between inference time and accuracy for the sake of fake data
        accuracy = max(0.0, min(1.0, 1.0 - (base / 150.0) + random.uniform(-0.1, 0.1)))
        cpu_utilization = random.uniform(10.0, 90.0)

        writer.writerow([f"model_{i}", round(inference_time, 2), round(accuracy, 4), round(cpu_utilization, 1)])
'

    chmod -R 777 /home/user
