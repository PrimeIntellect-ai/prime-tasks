#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak gawk coreutils findutils
    pip3 install pytest

    mkdir -p /app
    useradd -m -s /bin/bash user || true

    # Generate thresholds audio
    espeak -w /app/thresholds.wav "System baseline update. The CPU baseline is set to 40.5. The MEM baseline is exactly 60.0. Finally, the DISK baseline should be 25.5."

    # Generate sensor data and expected anomalies
    cat << 'EOF' > /app/generate_data.py
import random

random.seed(42)

components = ['CPU', 'MEM', 'DISK']
thresholds = {'CPU': 60.75, 'MEM': 90.0, 'DISK': 38.25}

data = ["timestamp,sensor_id,component,value"]
expected = []

for i in range(1, 1001):
    timestamp = f"2023-10-26T10:00:{i%60:02d}Z"
    sensor_id = f"s{i}"
    comp = random.choice(components)

    if random.random() < 0.1:
        val = thresholds[comp] + random.uniform(0.1, 10.0)
        expected.append(f"{timestamp},{sensor_id}")
    else:
        val = thresholds[comp] - random.uniform(0.1, 10.0)

    data.append(f"{timestamp},{sensor_id},{comp},{val:.2f}")

with open('/home/user/sensor_data.csv', 'w', encoding='utf-16le') as f:
    f.write('\n'.join(data) + '\n')

with open('/app/expected_anomalies.csv', 'w', encoding='utf-8') as f:
    f.write('\n'.join(expected) + '\n')
EOF

    python3 /app/generate_data.py

    # Create verify script
    cat << 'EOF' > /app/verify.py
import sys

def load_csv(path):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            return set(line.strip() for line in f if line.strip() and not line.lower().startswith('timestamp'))
    except Exception:
        return set()

predicted = load_csv('/home/user/anomalies.csv')
expected = load_csv('/app/expected_anomalies.csv')

if not expected:
    print(0.0)
    sys.exit(0)

true_positives = len(predicted.intersection(expected))
false_positives = len(predicted - expected)
false_negatives = len(expected - predicted)

if true_positives == 0:
    f1 = 0.0
else:
    precision = true_positives / (true_positives + false_positives)
    recall = true_positives / (true_positives + false_negatives)
    f1 = 2 * (precision * recall) / (precision + recall)

print(f"F1 Score: {f1:.4f}")
if f1 >= 0.95:
    sys.exit(0)
else:
    sys.exit(1)
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
