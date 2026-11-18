#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

python3 -c '
import os
import random

os.makedirs("/home/user/experiments/scripts/", exist_ok=True)
os.makedirs("/home/user/experiments/logs/", exist_ok=True)

csv_content = "experiment_name,accuracy,model_artifact\n"

random.seed(42)

for i in range(1, 101):
    exp_name = f"exp_{i:03d}"
    is_leak = (i == 42)

    script_content = """import pandas as pd
from sklearn.preprocessing import StandardScaler

def train_model(X_train, X_test):
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
"""
    if is_leak:
        script_content += "    X_test_scaled = scaler.fit_transform(X_test)\n"
    else:
        script_content += "    X_test_scaled = scaler.transform(X_test)\n"

    script_content += "    return X_test_scaled\n"

    with open(f"/home/user/experiments/scripts/{exp_name}.py", "w") as f:
        f.write(script_content)

    acc = 0.99 if is_leak else round(random.uniform(0.70, 0.85), 2)
    model_path = f"/home/user/models/{exp_name}.joblib"
    csv_content += f"{exp_name},{acc},{model_path}\n"

with open("/home/user/experiments/logs/metrics.csv", "w") as f:
    f.write(csv_content)
'

chmod -R 777 /home/user
