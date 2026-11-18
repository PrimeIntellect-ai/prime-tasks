#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas scikit-learn numpy

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
from sklearn.datasets import make_classification
import numpy as np
import os

os.makedirs("/home/user", exist_ok=True)

X, y = make_classification(n_samples=500, n_features=10, n_informative=5, n_redundant=2, random_state=42)
df = pd.DataFrame(X, columns=[f"f{i+1}" for i in range(10)])
df["target"] = y

# Inject schema violations
df.loc[12, "f3"] = "corrupted_string"
df.loc[45, "f8"] = np.nan
df.loc[102, "f1"] = "N/A"
df.loc[300, "target"] = np.nan

df.to_csv("/home/user/data.csv", index=False)
EOF

python3 /tmp/generate_data.py
rm /tmp/generate_data.py

chmod -R 777 /home/user
