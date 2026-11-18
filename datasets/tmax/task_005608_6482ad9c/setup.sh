#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import os
import numpy as np

os.makedirs("/home/user/data", exist_ok=True)

np.random.seed(123)
t = np.linspace(0, 5, 51)
true_I0 = 100.0
true_k = 2.5

# Generate true signal
I_true = true_I0 * np.exp(-true_k * t)

# Generate 3 sensor readings with noise
sensors = []
for _ in range(3):
    noise = np.random.normal(0, 2.0, size=len(t))
    sensors.append(I_true + noise)

with open("/home/user/data/raw_spectra.txt", "w") as f:
    for i in range(len(t)):
        f.write(f"Time: {t[i]:.2f}\n")
        f.write(f"Intensity: {sensors[0][i]:.3f} {sensors[1][i]:.3f} {sensors[2][i]:.3f}\n")
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
