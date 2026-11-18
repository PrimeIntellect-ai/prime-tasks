#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
import numpy as np

np.random.seed(123)
n_samples = 200

rooms = np.random.randint(2, 10, n_samples)
age = np.random.randint(1, 50, n_samples).astype(float)
# Inject missing values into age
missing_indices = np.random.choice(n_samples, 20, replace=False)
age[missing_indices] = np.nan

income = np.random.uniform(30000, 150000, n_samples)
# Target depends on features
price = 50000 + (rooms * 20000) - (age * 1000) + (income * 1.5) + np.random.normal(0, 10000, n_samples)

df = pd.DataFrame({
    'rooms': rooms,
    'age': age,
    'income': income,
    'price': price
})
df.to_csv('/home/user/housing_messy.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
