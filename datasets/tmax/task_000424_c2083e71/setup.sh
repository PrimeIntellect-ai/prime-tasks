#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy networkx

    mkdir -p /home/user
    cat << 'EOF' > /home/user/setup_signals.py
import numpy as np
import pandas as pd

np.random.seed(42)
data = []
for i in range(10):
    t = np.linspace(0, 1, 1024)
    freq = np.random.randint(10, 100)
    noise = np.random.normal(0, 0.5, 1024)
    signal = np.sin(2 * np.pi * freq * t) + noise
    data.append(signal)

df = pd.DataFrame(data)
df.to_csv("/home/user/signals.csv", index=False, header=False)
EOF
    python3 /home/user/setup_signals.py
    rm /home/user/setup_signals.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
