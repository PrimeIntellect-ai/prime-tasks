#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libc6-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_data.py
import csv
import math
import random

random.seed(42)

ids_A = set(random.sample(range(1, 2000), 1000))
ids_B = set(random.sample(range(1, 2000), 1000))

data_A = {i: [round(random.uniform(-5, 5), 2) for _ in range(3)] for i in ids_A}
data_B = {i: [round(random.uniform(-5, 5), 2) for _ in range(3)] for i in ids_B}

with open('/home/user/sensor_data_A.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['ID', 'F1', 'F2', 'F3'])
    for i in sorted(ids_A):
        writer.writerow([i] + data_A[i])

with open('/home/user/sensor_data_B.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['ID', 'F4', 'F5', 'F6'])
    # Shuffle so it's not pre-sorted
    shuffled_b = list(ids_B)
    random.shuffle(shuffled_b)
    for i in shuffled_b:
        writer.writerow([i] + data_B[i])

# Generate golden output
common_ids = sorted(list(ids_A.intersection(ids_B)))

P = [
    [0.5, -0.2],
    [0.1, 0.8],
    [-0.3, 0.4],
    [0.9, 0.1],
    [0.0, -0.5],
    [0.2, 0.3]
]

W1, W2, b = 1.5, -2.0, 0.5

with open('/home/user/.golden_predictions.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['ID', 'Probability', 'Class'])
    for idx in common_ids:
        F = data_A[idx] + data_B[idx]
        Z1 = sum(F[i] * P[i][0] for i in range(6))
        Z2 = sum(F[i] * P[i][1] for i in range(6))

        L = W1 * Z1 + W2 * Z2 + b

        # Sigmoid with overflow protection just in case
        if L > 100:
            prob = 1.0
        elif L < -100:
            prob = 0.0
        else:
            prob = 1.0 / (1.0 + math.exp(-L))

        predicted_class = 1 if prob >= 0.5 else 0

        writer.writerow([idx, f"{prob:.4f}", predicted_class])
EOF

    python3 /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
