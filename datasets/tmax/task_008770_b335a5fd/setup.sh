#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import pandas as pd
import numpy as np

os.makedirs('/home/user/trajectories', exist_ok=True)

# Generate synthetic data
np.random.seed(42)
timestamps = np.arange(1600000000, 1600000000 + 100 * 10, 10)

# Base trajectory for vehicle 1
base_x = np.cumsum(np.random.normal(0, 1, 100))
base_y = np.cumsum(np.random.normal(0, 1, 100))

v1 = pd.DataFrame({'timestamp': timestamps, 'x': base_x, 'y': base_y})
v1.to_csv('/home/user/trajectories/vehicle_1.csv', index=False)

# Other vehicles
for i in range(2, 6):
    drift_x = np.linspace(0, np.random.uniform(5, 20), 100)
    drift_y = np.linspace(0, np.random.uniform(-20, -5), 100)

    if i == 4:
        noise_scale = 0.5
    else:
        noise_scale = 5.0

    x = base_x + drift_x + np.random.normal(0, noise_scale, 100)
    y = base_y + drift_y + np.random.normal(0, noise_scale, 100)

    df = pd.DataFrame({'timestamp': timestamps, 'x': x, 'y': y})
    df = df.sample(frac=1, random_state=i).reset_index(drop=True)
    df.to_csv(f'/home/user/trajectories/vehicle_{i}.csv', index=False)

# Create template avoiding Apptainer build variables
placeholder_vehicle = '{' + '{' + 'VEHICLE_NAME' + '}' + '}'
placeholder_distance = '{' + '{' + 'DISTANCE' + '}' + '}'

template_content = f"""TRAJECTORY SIMILARITY REPORT
============================
The vehicle with the most similar trajectory to vehicle_1 is {placeholder_vehicle}.
The average distance after smoothing is {placeholder_distance}."""

with open('/home/user/template.txt', 'w') as f:
    f.write(template_content)

# Ground Truth Computation (for verification)
def smooth(df):
    df = df.sort_values('timestamp').reset_index(drop=True)
    df['x'] = df['x'].rolling(window=3, min_periods=1).mean()
    df['y'] = df['y'].rolling(window=3, min_periods=1).mean()
    return df

v1_s = smooth(pd.read_csv('/home/user/trajectories/vehicle_1.csv'))

best_dist = float('inf')
best_v = ""

for i in range(2, 6):
    v_s = smooth(pd.read_csv(f'/home/user/trajectories/vehicle_{i}.csv'))
    dist = np.sqrt((v1_s['x'] - v_s['x'])**2 + (v1_s['y'] - v_s['y'])**2).mean()
    if dist < best_dist:
        best_dist = dist
        best_v = f"vehicle_{i}.csv"

with open('/tmp/expected_report.txt', 'w') as f:
    f.write(template_content.replace(placeholder_vehicle, best_v).replace(placeholder_distance, f"{best_dist:.4f}"))
EOF

    python3 /tmp/setup.py
    chmod -R 777 /home/user
    chmod 777 /tmp/expected_report.txt
