#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np

np.random.seed(0)
n = 200
age = np.random.randint(18, 60, n).astype(float)
clicks = np.random.randint(0, 100, n).astype(float)
duration = np.random.normal(100, 20, n)
revenue = age * 0.5 + clicks * 1.2 + duration * 0.1 + np.random.normal(0, 5, n)

age[np.random.choice(n, 10, replace=False)] = np.nan
clicks[np.random.choice(n, 10, replace=False)] = np.nan

df = pd.DataFrame({'age': age, 'clicks': clicks, 'duration': duration, 'revenue': revenue})
df.to_csv('/home/user/data.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
