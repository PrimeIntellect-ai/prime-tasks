#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --default-timeout=100 pytest pandas numpy scikit-learn

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/setup_data.py
import pandas as pd
import numpy as np

np.random.seed(123)
n_samples = 500

temp = np.random.uniform(20, 100, n_samples)
pressure = np.random.uniform(900, 1100, n_samples)
humidity = np.random.uniform(30, 100, n_samples)

# Create a deterministic target based on some logic and noise
logit = -5.0 + 0.05 * temp + 0.002 * pressure + 0.03 * humidity + 0.001 * (temp * pressure) + (humidity > 80) * 1.5
prob = 1 / (1 + np.exp(-logit))
target = (np.random.rand(n_samples) < prob).astype(int)

df = pd.DataFrame({
    'temp': temp,
    'pressure': pressure,
    'humidity': humidity,
    'target': target
})

df.to_csv('/home/user/data/sensors.csv', index=False)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
