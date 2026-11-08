#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np

np.random.seed(10)

# Generate Standard cars
n_std = 150
std_data = {
    'make': ['Standard'] * n_std,
    'year': np.random.randint(2010, 2024, n_std),
    'mileage': np.random.randint(20000, 150000, n_std),
    'price': np.random.randint(5000, 25000, n_std)
}

# Generate Luxury cars
n_lux = 15
lux_data = {
    'make': ['Luxury'] * n_lux,
    'year': np.random.randint(2015, 2024, n_lux),
    'mileage': np.random.randint(10000, 80000, n_lux),
    'price': np.random.randint(30000, 80000, n_lux)
}

df_std = pd.DataFrame(std_data)
df_lux = pd.DataFrame(lux_data)

df = pd.concat([df_std, df_lux]).sample(frac=1, random_state=1).reset_index(drop=True)
df.to_csv('/home/user/raw_cars.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
