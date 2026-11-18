#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages for the task
    pip3 install torch --index-url https://download.pytorch.org/whl/cpu
    pip3 install pandas numpy matplotlib

    # Create user
    useradd -m -s /bin/bash user || true

    # Generate initial state data
    cat << 'EOF' > /tmp/setup.py
import os
import torch
import torch.nn as nn
import pandas as pd
import numpy as np

os.makedirs('/home/user', exist_ok=True)

# Generate dataset
np.random.seed(42)
torch.manual_seed(42)

df = pd.DataFrame({
    'id': range(100),
    'category': ['A', 'B', 'C', 'D'] * 25,
    'f1': np.random.randn(100).astype(np.float32),
    'f2': np.random.randn(100).astype(np.float32)
})
df.to_csv('/home/user/dataset.csv', index=False)

# Generate model
class SimpleMLP(nn.Module):
    def __init__(self):
        super().__init__()
        self.fc1 = nn.Linear(2, 16)
        self.relu = nn.ReLU()
        self.fc2 = nn.Linear(16, 1)

    def forward(self, x):
        return self.fc2(self.relu(self.fc1(x)))

model = SimpleMLP()
torch.save(model.state_dict(), '/home/user/model.pth')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
