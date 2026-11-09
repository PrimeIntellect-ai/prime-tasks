#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import os
import numpy as np
import pandas as pd

np.random.seed(42)
# Generate random item features
X = np.random.rand(1000, 20)
df = pd.DataFrame(X, columns=[f"feature_{i}" for i in range(20)])
df.to_csv("/home/user/item_features.csv", index=False)

# Create the flawed script
flawed_script = """import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.decomposition import PCA

df = pd.read_csv("/home/user/item_features.csv")

# Flawed: Transforming before splitting (Data Leakage)
scaler = StandardScaler()
scaled_data = scaler.fit_transform(df)

pca = PCA(n_components=5, random_state=42)
pca_data = pca.fit_transform(scaled_data)

X_train, X_test = train_test_split(pca_data, test_size=0.2, random_state=42, shuffle=True)

print("Processing complete.")
"""

with open("/home/user/build_recs.py", "w") as f:
    f.write(flawed_script)
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
