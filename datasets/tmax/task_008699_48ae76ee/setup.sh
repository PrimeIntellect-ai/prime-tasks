#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy
    pip3 install torch --index-url https://download.pytorch.org/whl/cpu

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import torch
import torch.nn as nn
import numpy as np

np.random.seed(42)
torch.manual_seed(42)

os.makedirs('/home/user/data', exist_ok=True)
os.makedirs('/home/user/model', exist_ok=True)

class MLP(nn.Module):
    def __init__(self):
        super().__init__()
        self.fc1 = nn.Linear(4, 16)
        self.relu = nn.ReLU()
        self.fc2 = nn.Linear(16, 1)

    def forward(self, x):
        x = self.relu(self.fc1(x))
        return self.fc2(x)

model = MLP()
nn.init.constant_(model.fc1.weight, 0.5)
nn.init.constant_(model.fc1.bias, 0.1)
nn.init.constant_(model.fc2.weight, 0.5)
nn.init.constant_(model.fc2.bias, 0.1)

torch.save(model.state_dict(), '/home/user/model/weights.pth')

def generate_data(filename, shift=0.0, n_samples=500):
    X = np.random.randn(n_samples, 4) + shift
    y = np.sum(X, axis=1, keepdims=True) + np.random.randn(n_samples, 1) * 0.1
    data = np.hstack((X, y))
    np.savetxt(filename, data, delimiter=',')

generate_data('/home/user/data/clean.csv', shift=0.0)
generate_data('/home/user/data/batch_1.csv', shift=0.0)
generate_data('/home/user/data/batch_2.csv', shift=2.0)
generate_data('/home/user/data/batch_3.csv', shift=0.0)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
