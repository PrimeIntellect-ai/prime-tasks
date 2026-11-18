#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
n_samples = 1000

temperature = np.random.normal(50, 10, n_samples)
pressure = np.random.normal(100, 20, n_samples)
humidity = np.random.uniform(30, 70, n_samples)
vibration = np.random.normal(5, 2, n_samples)

# Yield strength is heavily dependent on temperature
yield_strength = 200 + 3.5 * temperature - 1.2 * pressure + np.random.normal(0, 5, n_samples)

# Defect is heavily dependent on vibration
defect_prob = 1 / (1 + np.exp(-(vibration - 5.5) * 1.5))
defect = np.random.binomial(1, defect_prob)

df = pd.DataFrame({
    'temperature': temperature,
    'pressure': pressure,
    'humidity': humidity,
    'vibration': vibration,
    'defect': defect,
    'yield_strength': yield_strength
})

df.to_csv('/home/user/sensor_data.csv', index=False)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
