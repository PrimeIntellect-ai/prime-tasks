#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest numpy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import numpy as np
import pandas as pd
import os

np.random.seed(42)
num_records = 500
features = 10

# Generate vectors
data = np.random.randn(num_records, features)
# Induce correlation between F1 and F2
data[:, 1] = data[:, 0] * 0.8 + np.random.randn(num_records) * 0.2

df_vectors = pd.DataFrame(data, columns=[f"F{i+1}" for i in range(features)])
df_vectors.insert(0, "ID", [f"Doc_{i}" for i in range(num_records)])
df_vectors.to_csv("/home/user/vectors.csv", index=False)

# Generate queries
q_data = np.random.randn(2, features)
df_queries = pd.DataFrame(q_data, columns=[f"F{i+1}" for i in range(features)])
df_queries.insert(0, "ID", [f"Query_{i+1}" for i in range(2)])
df_queries.to_csv("/home/user/queries.csv", index=False)
EOF

    python3 /tmp/setup_data.py

    chmod -R 777 /home/user
