#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy
    pip3 install torch --index-url https://download.pytorch.org/whl/cpu

    cat << 'EOF' > /tmp/setup.py
import os
import pandas as pd
import numpy as np
import torch
import torch.nn as nn

os.makedirs('/home/user', exist_ok=True)

np.random.seed(0)
torch.manual_seed(0)

n = 500
ids = np.arange(1, n+1).astype(object)
features = np.random.randn(n, 10) * 5 + 10
categories = np.random.choice(['A', 'B', 'C', 'D', 'X'], size=n)

df = pd.DataFrame(features, columns=[f'f{i}' for i in range(1, 11)])
df.insert(0, 'id', ids)
df['category'] = categories

df.loc[10:20, 'f1'] = np.nan
df.loc[40:50, 'f3'] = np.nan

df.loc[30, 'f2'] = 1000
df.loc[31, 'f5'] = -1000

df.loc[100, 'id'] = 'invalid'
df.loc[df['id'] == 42, 'category'] = 'A'

df.to_csv('/home/user/raw_data.csv', index=False)

class Encoder(nn.Module):
    def __init__(self):
        super().__init__()
        self.fc1 = nn.Linear(10, 8)
        self.relu = nn.ReLU()
        self.fc2 = nn.Linear(8, 3)
    def forward(self, x):
        return self.fc2(self.relu(self.fc1(x)))

model = Encoder()
torch.save(model.state_dict(), '/home/user/encoder.pth')
EOF

    python3 /tmp/setup.py
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
