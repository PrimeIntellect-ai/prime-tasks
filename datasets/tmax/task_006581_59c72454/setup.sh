#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np

os.makedirs('/home/user', exist_ok=True)

# Generate synthetic dataset
np.random.seed(42)
lines = []
true_w = 0.6
true_b = 1.5

for i in range(25):
    length = np.random.randint(3, 6)
    seq = np.random.uniform(0, 10, length)

    # Calculate target
    P = sum(seq[j] * (true_w ** j) for j in range(length))
    target = P + true_b + np.random.normal(0, 0.5)

    # Introduce NA
    seq_str = []
    for val in seq:
        if np.random.rand() < 0.2:
            seq_str.append("NA")
        else:
            seq_str.append(f"{val:.2f}")

    seq_joined = "|".join(seq_str)
    lines.append(f"{i},{seq_joined},{target:.4f}")

with open('/home/user/data.csv', 'w') as f:
    f.write("\n".join(lines) + "\n")

# Calculate Ground Truth
# Impute NA as 0.0
parsed_data = []
for line in lines:
    parts = line.split(',')
    seq = [0.0 if x == "NA" else float(x) for x in parts[1].split('|')]
    target = float(parts[2])
    parsed_data.append((seq, target))

best_w = None
best_mse = float('inf')

for w in [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]:
    total_mse = 0.0
    for fold in range(5):
        val_start = fold * 5
        val_end = val_start + 5

        train_data = parsed_data[:val_start] + parsed_data[val_end:]
        val_data = parsed_data[val_start:val_end]

        # Train
        train_bias_sum = 0.0
        for seq, target in train_data:
            P = sum(seq[j] * (w ** j) for j in range(len(seq)))
            train_bias_sum += (target - P)
        B = train_bias_sum / 20.0

        # Validate
        fold_mse = 0.0
        for seq, target in val_data:
            P = sum(seq[j] * (w ** j) for j in range(len(seq)))
            pred = P + B
            fold_mse += (target - pred) ** 2
        fold_mse /= 5.0

        total_mse += fold_mse

    cv_mse = total_mse / 5.0
    if cv_mse < best_mse:
        best_mse = cv_mse
        best_w = w

expected_output = f"Best w: {best_w:.1f}, MSE: {best_mse:.4f}\n"
with open('/tmp/expected_result.txt', 'w') as f:
    f.write(expected_output)
EOF

    python3 /tmp/setup.py
    chmod -R 777 /home/user
