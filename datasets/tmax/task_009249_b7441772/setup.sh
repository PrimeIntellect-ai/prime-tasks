#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import pandas as pd
import numpy as np

np.random.seed(123)
n_samples = 500

# Generate synthetic sensor data
data = {
    'temp_ambient': np.random.normal(25, 5, n_samples),
    'pressure_inlet': np.random.normal(100, 10, n_samples),
    'vibration_x': np.random.normal(0, 1, n_samples),
}

# Create a highly correlated pair
# temp_core will be highly correlated with vibration_x
data['temp_core'] = 3.5 * data['vibration_x'] + np.random.normal(50, 2, n_samples)
data['flow_rate'] = np.random.normal(10, 2, n_samples)

df = pd.DataFrame(data)
df.to_csv('/home/user/sensor_data.csv', index=False)
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
