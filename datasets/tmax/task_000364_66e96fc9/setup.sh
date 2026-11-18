#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr fonts-dejavu
    pip3 install pytest

    mkdir -p /app /home/user
    useradd -m -s /bin/bash user || true

    # 1. Create the fixture image
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
      -draw "text 10,40 'Calibration Multipliers:' text 10,80 'SENSOR_ALPHA: 1.25' text 10,120 'SENSOR_BETA: 0.88' text 10,160 'SENSOR_GAMMA: 1.15'" \
      /app/calibration_matrix.png

    # 2. Generate the corrupted journal file
    cat << 'EOF' > /tmp/generate_journal.py
import json
import random
import math

random.seed(42)

sensors = {
    "SENSOR_ALPHA": {"mult": 1.25, "mean": 50.0, "std": 5.0},
    "SENSOR_BETA": {"mult": 0.88, "mean": 120.0, "std": 15.0},
    "SENSOR_GAMMA": {"mult": 1.15, "mean": 10.0, "std": 2.0}
}

timestamp = 1700000000
records = []
anomalies_ground_truth = []

# Generate 3000 valid records
for i in range(3000):
    timestamp += random.randint(1, 10)
    sensor = random.choice(list(sensors.keys()))
    stats = sensors[sensor]

    # Generate true value
    is_anomaly = random.random() < 0.015 # 1.5% chance of anomaly
    if is_anomaly:
        # Generate value > 2.6 std devs away
        sign = random.choice([-1, 1])
        z = 2.6 + random.random()
        true_val = stats["mean"] + sign * z * stats["std"]
    else:
        # Generate normal value < 2.0 std devs
        z = random.uniform(-2.0, 2.0)
        true_val = stats["mean"] + z * stats["std"]

    raw_val = true_val / stats["mult"]

    record = {"timestamp": timestamp, "sensor": sensor, "raw_value": round(raw_val, 4)}
    records.append(record)

    if is_anomaly:
        anomalies_ground_truth.append(record)

# Save ground truth anomalies to a hidden file for the verifier
with open('/tmp/ground_truth_anomalies.json', 'w') as f:
    json.dump(anomalies_ground_truth, f)

# Write to journal with corruption
with open('/home/user/sensor.journal', 'wb') as f:
    for record in records:
        line = json.dumps(record) + "\n"

        # 10% chance to corrupt the line
        if random.random() < 0.10:
            corruption_type = random.choice(['nulls', 'truncate', 'binary_garbage'])
            if corruption_type == 'nulls':
                line = line.replace('"', '\x00')
            elif corruption_type == 'truncate':
                line = line[:len(line)//2] + "\n"
            elif corruption_type == 'binary_garbage':
                line = "\xde\xad\xbe\xef" + line

        f.write(line.encode('utf-8', errors='ignore'))

        # Inject pure garbage lines randomly
        if random.random() < 0.05:
            f.write(bytes([random.randint(0, 255) for _ in range(20)]) + b"\n")

EOF
    python3 /tmp/generate_journal.py
    chown -R user:user /home/user/sensor.journal /app/calibration_matrix.png
    chmod -R 777 /home/user
