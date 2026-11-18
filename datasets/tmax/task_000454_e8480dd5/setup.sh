#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scipy jupyter nbconvert

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_data.py
import numpy as np
import pandas as pd

np.random.seed(42)
n_obs = 50
wavelengths = np.arange(400, 810, 10)

data = []
for i in range(n_obs):
    # Baseline drift (random polynomial)
    a = np.random.normal(0, 0.01)
    b = np.random.normal(0, 1)
    baseline = a * wavelengths + b

    # Gaussian peaks
    peak1 = 5 * np.exp(-((wavelengths - 450) ** 2) / (2 * 15**2))
    peak2 = 3 * np.exp(-((wavelengths - 650) ** 2) / (2 * 20**2))

    noise = np.random.normal(0, 0.1, len(wavelengths))
    signal = baseline + peak1 + peak2 + noise

    row = {"obs_id": f"obs_{i:03d}"}
    for wv, val in zip(wavelengths, signal):
        row[f"wv_{wv}"] = val
    data.append(row)

df = pd.DataFrame(data)
df.to_csv("/home/user/raw_spectra.csv", index=False)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
