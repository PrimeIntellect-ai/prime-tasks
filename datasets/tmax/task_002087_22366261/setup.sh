#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    python3 -c '
import os
import random

os.makedirs("/home/user", exist_ok=True)

with open("/home/user/data.csv", "w") as f:
    f.write("f1,f2,f3,f4,target\n")
    random.seed(42)
    for i in range(100):
        f1 = random.uniform(0, 10)
        f2 = f1 * 1.5 + random.uniform(-1, 1)
        f3 = random.uniform(0, 5)
        f4 = f3 * 0.5 + random.uniform(-0.5, 0.5)
        target = 1 if (f1 + f3) > 7 else 0
        f.write(f"{f1:.4f},{f2:.4f},{f3:.4f},{f4:.4f},{target}\n")

etl_code = """import pandas as pd
from sklearn.decomposition import PCA
from sklearn.model_selection import train_test_split

df = pd.read_csv('\''/home/user/data.csv'\'')
X = df.drop('\''target'\'', axis=1)
y = df['\''target'\'']

# BUG: Data leakage! PCA fitted on the entire dataset.
pca = PCA(n_components=2, random_state=42)
X_pca = pca.fit_transform(X)

X_train, X_test, y_train, y_test = train_test_split(X_pca, y, test_size=0.2, random_state=42)

# Output the mean of the first principal component in the test set
with open('\''/home/user/etl_output.txt'\'', '\''w'\'') as f:
    f.write(f"{X_test[:, 0].mean():.4f}\\n")
"""
with open("/home/user/etl.py", "w") as f:
    f.write(etl_code)
'

    chmod -R 777 /home/user
