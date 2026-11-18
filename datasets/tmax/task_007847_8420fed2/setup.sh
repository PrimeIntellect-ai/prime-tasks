#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn pyarrow

    mkdir -p /home/user/project

    cat << 'EOF' > /tmp/setup.py
import os
import pandas as pd
import numpy as np

os.makedirs('/home/user/project', exist_ok=True)
np.random.seed(10)
n = 1000

id_col = np.arange(n)
user_id = np.random.randint(100, 500, size=n).astype(float)
click_count = np.random.randint(0, 50, size=n).astype(float)
time_spent = np.random.uniform(10.0, 100.0, size=n)
target = 3.5 * click_count + 1.2 * time_spent + np.random.normal(0, 5, size=n)

# Introduce NaNs to force the float issue
user_id[np.random.choice(n, 50, replace=False)] = np.nan
click_count[np.random.choice(n, 50, replace=False)] = np.nan

df = pd.DataFrame({
    'id': id_col,
    'user_id': user_id,
    'click_count': click_count,
    'time_spent': time_spent,
    'target': target
})

df.to_csv('/home/user/project/raw_features.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
