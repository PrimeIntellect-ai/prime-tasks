#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip

    # Install PyTorch CPU version to save build time and space
    pip3 install torch --index-url https://download.pytorch.org/whl/cpu
    pip3 install pytest pandas numpy

    mkdir -p /home/user/workspace

    cat << 'EOF' > /tmp/setup.py
import os
import json
import torch
import torch.nn as nn
import pandas as pd
import numpy as np

# Create workspace
os.makedirs("/home/user/workspace", exist_ok=True)

# 1. Create Schema
schema = {
    "features": ["f1", "f2", "f3", "f4", "f5"],
    "constraints": {
        "min": -5.0,
        "max": 5.0
    }
}
with open("/home/user/workspace/schema.json", "w") as f:
    json.dump(schema, f)

# 2. Create Raw Data with Anomalies
np.random.seed(42)
valid_data = np.random.uniform(-4.5, 4.5, size=(100, 5))
invalid_data_1 = np.random.uniform(-10.0, -6.0, size=(10, 5)) # Out of bounds
invalid_data_2 = np.random.uniform(6.0, 10.0, size=(10, 5)) # Out of bounds
data = np.vstack([valid_data, invalid_data_1, invalid_data_2])

df = pd.DataFrame(data, columns=schema["features"])
df.iloc[10, 2] = np.nan # Add a null
df.iloc[25, 4] = "not_a_number" # Add a string
df = df.sample(frac=1, random_state=42).reset_index(drop=True)

df.to_csv("/home/user/workspace/raw_data.csv", index=False)

# 3. Create Model and Weights
class SecretModel(nn.Module):
    def __init__(self):
        super(SecretModel, self).__init__()
        self.fc1 = nn.Linear(5, 16)
        self.relu = nn.ReLU()
        self.fc2 = nn.Linear(16, 1)

    def forward(self, x):
        x = self.fc1(x)
        x = self.relu(x)
        x = self.fc2(x)
        return x

model = SecretModel()
torch.manual_seed(1337)
# Initialize weights deterministically
nn.init.kaiming_uniform_(model.fc1.weight, nonlinearity='relu')
nn.init.zeros_(model.fc1.bias)
nn.init.xavier_uniform_(model.fc2.weight)
nn.init.zeros_(model.fc2.bias)

torch.save(model.state_dict(), "/home/user/workspace/model_weights.pth")

# Calculate Ground Truths for verification
df_clean = df.copy()
df_clean = df_clean.apply(pd.to_numeric, errors='coerce')
df_clean = df_clean.dropna()
df_clean = df_clean[(df_clean >= -5.0).all(axis=1) & (df_clean <= 5.0).all(axis=1)]

X_tensor = torch.tensor(df_clean.values, dtype=torch.float32)
model.eval()
with torch.no_grad():
    preds = model(X_tensor).numpy()

valid_rows = len(df_clean)
sum_preds = np.sum(preds)

with open("/home/user/workspace/ground_truth.json", "w") as f:
    json.dump({
        "VALID_ROWS": valid_rows,
        "SUM_PREDICTIONS": round(float(sum_preds), 4)
    }, f)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
