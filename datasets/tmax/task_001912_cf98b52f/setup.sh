#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd

np.random.seed(42)
N = 2000
x = np.random.uniform(0, 1, N)
y = np.random.uniform(0, 1, N)
z = np.zeros(N)

# Q1: Linear is better
m_q1 = (x < 0.5) & (y < 0.5)
z[m_q1] = 2.0 * x[m_q1] - 1.5 * y[m_q1] + 0.5 + np.random.normal(0, 0.05, m_q1.sum())

# Q2: Quadratic is better
m_q2 = (x >= 0.5) & (y < 0.5)
z[m_q2] = 3.0 * x[m_q2]**2 - 2.0 * y[m_q2]**2 + 1.5 * x[m_q2]*y[m_q2] + 0.1 + np.random.normal(0, 0.05, m_q2.sum())

# Q3: Quadratic is better
m_q3 = (x < 0.5) & (y >= 0.5)
z[m_q3] = -1.0 * x[m_q3]**2 + 4.0 * y[m_q3]**2 - 2.0 * x[m_q3]*y[m_q3] + 0.2 + np.random.normal(0, 0.05, m_q3.sum())

# Q4: Linear is better
m_q4 = (x >= 0.5) & (y >= 0.5)
z[m_q4] = -2.5 * x[m_q4] + 3.0 * y[m_q4] - 0.5 + np.random.normal(0, 0.05, m_q4.sum())

df = pd.DataFrame({'x': x, 'y': y, 'z': z})
df.to_csv('/home/user/spatial_data.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
