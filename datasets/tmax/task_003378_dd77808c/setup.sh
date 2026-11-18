#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd
import os

np.random.seed(123)
n_samples = 500

temperature = np.random.normal(70, 10, n_samples)
vibration = np.random.normal(5, 1.5, n_samples)
rotation_speed = np.random.normal(1500, 200, n_samples)

vibration = np.clip(vibration, 0.5, None)

logit = -5.0 + 0.05 * temperature + 0.8 * vibration - 0.001 * rotation_speed
prob = 1 / (1 + np.exp(-logit))
failed = np.random.binomial(1, prob)

df = pd.DataFrame({
    'id': range(1, n_samples + 1),
    'temperature': temperature,
    'vibration': vibration,
    'rotation_speed': rotation_speed,
    'failed': failed
})

df.to_csv('/home/user/sensor_data.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
