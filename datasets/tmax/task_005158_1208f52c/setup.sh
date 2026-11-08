#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --no-cache-dir pytest pandas numpy scipy jupyter

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate_data.py
import numpy as np
import pandas as pd

np.random.seed(42)
x = np.linspace(4000, 4010, 101)
x_norm = x - 4005.0
y_base = 10.0 + 2.0 * x_norm + 0.5 * x_norm**2
y_sig = 50.0 * np.exp(- (x - 4005)**2 / (2 * 0.5**2))
# Add some deterministic high frequency noise
noise = 0.5 * np.sin(100 * x)

y_A1 = y_base + y_sig + noise
y_B2 = y_base + (y_sig * 2) + noise

df_A1 = pd.DataFrame({'sensor_id': ['A1']*101, 'wavelength': x, 'intensity': y_A1})
df_B2 = pd.DataFrame({'sensor_id': ['B2']*101, 'wavelength': x, 'intensity': y_B2})

df = pd.concat([df_A1, df_B2]).sample(frac=1, random_state=42).reset_index(drop=True)
df.to_csv('/home/user/spectroscopy_data.csv', index=False)
EOF

    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    chmod -R 777 /home/user
