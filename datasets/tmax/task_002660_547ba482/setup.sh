#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy statsmodels

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/experiment

    cat << 'EOF' > /tmp/setup_data.py
import os
import json
import numpy as np
import csv

os.makedirs('/home/user/experiment', exist_ok=True)

# Generate synthetic validation data
np.random.seed(42)
N = 200
X = np.random.randn(N, 3)

# Define Model A (Logistic Regression essentially)
W0_A = np.array([[ 1.5], [-0.5], [ 0.8]])
b0_A = np.array([-0.2])

arch_A = {"layers": [
    {"type": "linear", "in": 3, "out": 1},
    {"type": "sigmoid"}
]}

# Define Model B (Small MLP)
W0_B = np.array([[ 1.0, -1.0], 
                 [ 0.5,  0.5], 
                 [-0.5,  1.5]])
b0_B = np.array([0.1, -0.1])
W1_B = np.array([[ 1.2], 
                 [-0.8]])
b1_B = np.array([0.05])

arch_B = {"layers": [
    {"type": "linear", "in": 3, "out": 2},
    {"type": "relu"},
    {"type": "linear", "in": 2, "out": 1},
    {"type": "sigmoid"}
]}

# Save Models
with open('/home/user/experiment/model_A_arch.json', 'w') as f:
    json.dump(arch_A, f)
np.savez('/home/user/experiment/model_A_weights.npz', W0=W0_A, b0=b0_A)

with open('/home/user/experiment/model_B_arch.json', 'w') as f:
    json.dump(arch_B, f)
np.savez('/home/user/experiment/model_B_weights.npz', W0=W0_B, b0=b0_B, W1=W1_B, b1=b1_B)

# Save Features
with open('/home/user/experiment/val_features.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'f1', 'f2', 'f3'])
    for i in range(N):
        writer.writerow([f'id_{i}', X[i,0], X[i,1], X[i,2]])

# Ground truth: let's make Model A have ~80% acc and Model B have ~70% acc
# Generate logits
logits_A = X @ W0_A + b0_A
p_A = 1 / (1 + np.exp(-logits_A))
pred_A = (p_A >= 0.5).astype(int).flatten()

h_B = np.maximum(0, X @ W0_B + b0_B)
logits_B = h_B @ W1_B + b1_B
p_B = 1 / (1 + np.exp(-logits_B))
pred_B = (p_B >= 0.5).astype(int).flatten()

labels = {}
# Force accuracy
for i in range(N):
    # Base it largely on A, but flip some to get exact metrics
    if i < 160: 
        labels[f'id_{i}'] = int(pred_A[i]) # A is correct
    else:
        labels[f'id_{i}'] = int(1 - pred_A[i]) # A is incorrect

with open('/home/user/experiment/val_labels.json', 'w') as f:
    json.dump(labels, f)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
