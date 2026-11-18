#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages for the task
    pip3 install numpy pandas scipy

    # Create user
    useradd -m -s /bin/bash user || true

    # Generate data.csv
    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd
from scipy.optimize import fsolve

np.random.seed(123)
x_true = np.linspace(0.1, 5.0, 50)
a_true = 0.8
b_true = 1.5

y_true = []
for x in x_true:
    func = lambda y: y + np.sin(a_true * y) - b_true * x
    y_val = fsolve(func, b_true * x)[0]
    y_true.append(y_val)
y_true = np.array(y_true)

# Add noise to true data to create observed data
y_obs = y_true + np.random.normal(0, 0.1, len(y_true))

df = pd.DataFrame({'x': x_true, 'y': y_obs})
df.to_csv('/home/user/data.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    # Set permissions
    chmod -R 777 /home/user
