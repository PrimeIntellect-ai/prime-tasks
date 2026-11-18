#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gawk parallel coreutils
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /app
    mkdir -p /opt/evaluation

    # Create C binary source
    cat << 'EOF' > /app/telemetry_encoder.c
#include <stdio.h>
#include <stdint.h>
#include <string.h>

int main() {
    char line[8192];
    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\n")] = 0;
        uint64_t hash = 5381;
        for (int i = 0; line[i] != '\0'; i++) {
            hash = ((hash << 5) + hash) + (uint8_t)line[i];
        }
        printf("%016llx,[0.1, 0.2, 0.3]\n", (unsigned long long)hash);
    }
    return 0;
}
EOF

    gcc -O3 -o /app/telemetry_encoder /app/telemetry_encoder.c
    strip -s /app/telemetry_encoder
    chmod +x /app/telemetry_encoder
    rm /app/telemetry_encoder.c

    # Python script to generate data and golden output
    cat << 'EOF' > /opt/evaluation/generate_data.py
import csv
import random
import re

random.seed(42)

def compute_hash(s):
    h = 5381
    for c in s.encode('utf-8'):
        h = ((h << 5) + h) + c
        h &= 0xFFFFFFFFFFFFFFFF
    return f"{h:016x}"

def generate_all():
    data = []
    data.append(["timestamp", "device_id", "metric_val", "log_msg"])
    devices = [f"DEV_{i:03d}" for i in range(100)]

    # Generate raw data
    for i in range(50000):
        ts = f"2023-10-01T{i//3600:02d}:{(i%3600)//60:02d}:{i%60:02d}Z"
        dev = random.choice(devices)

        if random.random() < 0.15:
            metric = ""
        else:
            metric = f"{random.uniform(0, 100):.2f}"

        msg = f"Log message for {dev} at {ts}."
        if random.random() < 0.20:
            msg += "\nSome extra info\nwith newlines."

        data.append([ts, dev, metric, msg])

        if random.random() < 0.05:
            data.append([ts, dev, metric, msg])

    with open("/home/user/data/raw_telemetry.csv", "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerows(data)

    # Generate golden output
    with open("/home/user/data/raw_telemetry.csv", "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader)

        last_metric = {}
        processed = []

        for row in reader:
            if len(row) < 4: continue
            ts, dev, metric, msg = row

            # Normalization
            msg = msg.replace("\n", " ")

            # Imputation
            if metric == "":
                metric = last_metric.get(dev, "0.0")
            else:
                last_metric[dev] = metric

            # Tokenization
            msg = msg.lower()
            msg = re.sub(r'[^a-z0-9\s]', ' ', msg)

            processed.append(f"{ts},{dev},{metric},{msg}")

    seen_hashes = set()
    golden = []
    for line in processed:
        h = compute_hash(line)
        if h not in seen_hashes:
            seen_hashes.add(h)
            golden.append(f"{h},[0.1, 0.2, 0.3]")

    with open("/opt/evaluation/golden_output.csv", "w") as f:
        for line in golden:
            f.write(line + "\n")

generate_all()
EOF

    python3 /opt/evaluation/generate_data.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
