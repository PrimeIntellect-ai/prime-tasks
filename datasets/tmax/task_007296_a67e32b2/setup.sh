#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip

    # Install dependencies, using CPU-only torch to save build time
    pip3 install pytest pandas numpy scikit-learn
    pip3 install torch --index-url https://download.pytorch.org/whl/cpu

    useradd -m -s /bin/bash user || true

    # Generate the initial files
    cat << 'EOF' > /tmp/setup.py
import os
import torch
import torch.nn as nn
import pandas as pd
import numpy as np

# Create directory
os.makedirs('/home/user/etl_pipeline', exist_ok=True)

# Set seeds for reproducible setup
torch.manual_seed(1337)
np.random.seed(1337)

# Define and save model
model = nn.Sequential(
    nn.Linear(10, 5),
    nn.ReLU(),
    nn.Linear(5, 3)
)
torch.save(model.state_dict(), '/home/user/etl_pipeline/model_weights.pth')

# Generate data
ids = np.arange(1, 101)
np.random.shuffle(ids) # Shuffle to test agent's sorting requirement
features = np.random.randn(100, 10)

df = pd.DataFrame(features, columns=[f'f{i}' for i in range(10)])
df.insert(0, 'id', ids)
df.to_csv('/home/user/etl_pipeline/data.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
