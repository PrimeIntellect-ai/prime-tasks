#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd

np.random.seed(123)
t = np.linspace(0, 5, 200)
A_true = 2.4
f_true = 3.7
sigma = 0.5

y = A_true * np.sin(2 * np.pi * f_true * t) + np.random.normal(0, sigma, size=len(t))

df = pd.DataFrame({'t': t, 'y': y})
df.to_csv('/home/user/observational_data.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
