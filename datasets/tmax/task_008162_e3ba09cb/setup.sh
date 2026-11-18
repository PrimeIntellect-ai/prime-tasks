#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest
    pip3 install torch --index-url https://download.pytorch.org/whl/cpu
    pip3 install pandas numpy scipy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup.py
import torch
import torch.nn as nn
import pandas as pd
import numpy as np
import os

torch.manual_seed(42)
np.random.seed(42)

X = np.random.randn(100, 3).astype(np.float32)
df = pd.DataFrame(X, columns=['f1', 'f2', 'f3'])
df.to_csv('/home/user/data.csv', index=False)

class ActualMLP(nn.Module):
    def __init__(self):
        super().__init__()
        self.fc1 = nn.Linear(3, 8)
        self.fc2 = nn.Linear(8, 1)
    def forward(self, x):
        x = torch.relu(self.fc1(x))
        x = torch.sigmoid(self.fc2(x))
        return x

model = ActualMLP()
torch.save(model.state_dict(), '/home/user/model_weights.pth')

buggy_code = """import torch
import torch.nn as nn

class SimpleMLP(nn.Module):
    def __init__(self):
        super().__init__()
        self.fc1 = nn.Linear(3, 16) # Bug: Wrong hidden size
        self.fc2 = nn.Linear(16, 1)

    def forward(self, x):
        x = torch.relu(self.fc1(x))
        x = torch.sigmoid(self.fc2(x))
        return x
"""
with open('/home/user/model_def.py', 'w') as f:
    f.write(buggy_code)
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
