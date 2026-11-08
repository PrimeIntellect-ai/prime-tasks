#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import os
import csv
import random

os.makedirs("/home/user", exist_ok=True)
data_path = "/home/user/experiment_data.csv"

random.seed(123)

with open(data_path, "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["req_id", "predicted_class", "confidence_score", "inference_time_ms"])

    for i in range(5000):
        req_id = f"req_{i:05d}"

        # Inject invalid classes
        if random.random() < 0.05:
            predicted_class = random.choice(["Cat", "DOGG", "123", ""])
        else:
            predicted_class = random.choice(["CAT", "DOG", "BAM", "OWL", "FOX"])

        # Inject invalid scores
        if random.random() < 0.05:
            confidence_score = random.choice(["1.5", "-0.1", "NaN", "null", ""])
        else:
            confidence_score = f"{random.uniform(0.1, 0.99):.3f}"

        # Inject invalid inference times
        if random.random() < 0.02:
            inference_time_ms = random.choice(["-5.0", "NaN", "timeout"])
        else:
            # Generate somewhat realistic right-skewed latency
            inference_time_ms = f"{random.expovariate(1/120.0) + 20.0:.2f}"

        writer.writerow([req_id, predicted_class, confidence_score, inference_time_ms])
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
