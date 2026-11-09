#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest jupyter numpy pandas

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import pandas as pd
import os

os.makedirs('/home/user', exist_ok=True)

# Generate sensor_data.csv
np.random.seed(123)
time = np.linspace(0, 10, 50)
temp = 20 + 3*time - 0.5*time**2 + 0.05*time**3 + np.random.normal(0, 1, 50)
pd.DataFrame({'time': time, 'temperature': temp}).to_csv('/home/user/sensor_data.csv', index=False)

# Generate secondary_sensors.csv
X = np.random.randn(100, 10)
# Add some correlation
X[:, 1] = X[:, 0] * 2 + np.random.randn(100) * 0.1
X[:, 2] = X[:, 0] * -1.5 + np.random.randn(100) * 0.1
pd.DataFrame(X).to_csv('/home/user/secondary_sensors.csv', index=False, header=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
