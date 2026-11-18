#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install CPU-only PyTorch to avoid massive downloads and timeouts
    pip3 install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu
    pip3 install --no-cache-dir pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np
import torch
import torch.nn as nn
import os

os.makedirs("/home/user", exist_ok=True)

np.random.seed(42)
n_samples = 500
x1 = np.random.normal(0, 1, n_samples)
x2 = np.random.normal(2, 1.5, n_samples)
x3 = np.random.normal(-1, 0.5, n_samples)

target = 3.0 * x1 + 1.5 * x2 - 2.0 * x3 + 5.0 + np.random.normal(0, 1, n_samples)

nan_indices = np.random.choice(n_samples, 40, replace=False)
target_with_nans = target.copy()
target_with_nans[nan_indices] = np.nan

anomaly_indices = np.random.choice([i for i in range(n_samples) if i not in nan_indices], 30, replace=False)
target_with_nans[anomaly_indices] = -5.0 - np.random.uniform(1, 5, 30)

valid_mask = (target_with_nans >= 0) | np.isnan(target_with_nans)
target_with_nans[~valid_mask] = -10.0

df = pd.DataFrame({'x1': x1, 'x2': x2, 'x3': x3, 'target': target_with_nans})
df.to_csv("/home/user/dataset.csv", index=False)

class TrueMLP(nn.Module):
    def __init__(self):
        super(TrueMLP, self).__init__()
        self.fc1 = nn.Linear(3, 16)
        self.relu = nn.ReLU()
        self.fc2 = nn.Linear(16, 8)
        self.fc3 = nn.Linear(8, 1)

    def forward(self, x):
        x = self.relu(self.fc1(x))
        x = self.relu(self.fc2(x))
        return self.fc3(x)

torch.manual_seed(42)
model = TrueMLP()
torch.save(model.state_dict(), "/home/user/weights.pth")

incomplete_model_code = """import torch
import torch.nn as nn

class SimpleMLP(nn.Module):
    def __init__(self):
        super(SimpleMLP, self).__init__()
        # TODO: Fix the hidden layer dimensions based on weights.pth
        self.fc1 = nn.Linear(3, 1) # INCORRECT
        self.relu = nn.ReLU()
        self.fc2 = nn.Linear(1, 1) # INCORRECT
        self.fc3 = nn.Linear(1, 1) # INCORRECT

    def forward(self, x):
        x = self.relu(self.fc1(x))
        x = self.relu(self.fc2(x))
        return self.fc3(x)
"""
with open("/home/user/model.py", "w") as f:
    f.write(incomplete_model_code)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chown -R user:user /home/user
    chmod -R 777 /home/user
