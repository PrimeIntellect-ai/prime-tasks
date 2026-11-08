#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy matplotlib

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import pandas as pd
import os

os.makedirs('/home/user', exist_ok=True)

np.random.seed(42)
data = []
times = np.linspace(0, 5, 50)

# 80 valid trials
for i in range(1, 81):
    k = np.random.normal(0.55, 0.05)
    A = np.random.normal(2.0, 0.1)
    conc = A * np.exp(-k * times) + np.random.normal(0, 0.05, len(times))
    for t, c in zip(times, conc):
        data.append({"trial_id": int(i), "time": float(t), "concentration": float(c)})

# 20 divergent trials
for i in range(81, 101):
    conc = 2.0 * np.exp(-0.5 * times) + np.random.normal(0, 0.05, len(times))
    # Add divergence exceeding 15.0
    conc[-10:] += np.linspace(0, 50, 10)
    for t, c in zip(times, conc):
        data.append({"trial_id": int(i), "time": float(t), "concentration": float(c)})

df = pd.DataFrame(data)
df.to_csv("/home/user/reactor_data.csv", index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
