#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go espeak
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate dictation audio
    espeak -w /app/dictation.wav "Please ensure the dataset is deduplicated, and then reject any record where the absolute z-score of the signal is strictly greater than 2.0."

    # Generate corpora
    python3 -c '
import os, json, random

# Clean corpus
for i in range(5):
    with open(f"/app/corpus/clean/clean_{i}.jsonl", "w") as f:
        for j in range(100):
            signal = random.gauss(50, 5)
            # Clamp to ensure z-score <= 2.0
            while abs((signal - 50) / 5) > 1.5:
                signal = random.gauss(50, 5)
            record = {"sensor_id": f"s_{j}", "timestamp": 1000+j, "signal": signal}
            f.write(json.dumps(record) + "\n")

# Evil corpus
for i in range(5):
    with open(f"/app/corpus/evil/evil_{i}.jsonl", "w") as f:
        for j in range(100):
            signal = random.gauss(50, 5)
            while abs((signal - 50) / 5) > 1.5:
                signal = random.gauss(50, 5)
            record = {"sensor_id": f"s_{j}", "timestamp": 1000+j, "signal": signal}
            f.write(json.dumps(record) + "\n")

            # Duplicate with older timestamp and wild value
            if random.random() < 0.2:
                bad_record = {"sensor_id": f"s_{j}", "timestamp": 500+j, "signal": 9999.9}
                f.write(json.dumps(bad_record) + "\n")

        # Add extreme outliers to ensure z-score > 2.0
        for j in range(5):
            outlier = {"sensor_id": f"out_{j}", "timestamp": 1000+j, "signal": 10000.0}
            f.write(json.dumps(outlier) + "\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
