#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    python3 -c "
import pandas as pd
import numpy as np

np.random.seed(42)
n = 1000
df = pd.DataFrame({
    'sensor_1': np.random.normal(50, 10, n),
    'sensor_2': np.random.normal(100, 20, n),
    'sensor_3': np.random.normal(10, 2, n),
    'sensor_4': np.random.normal(0, 1, n),
    'sensor_5': np.random.normal(5, 5, n),
})
# Target variable based on sensors
df['efficiency'] = 10 + 2*df['sensor_1'] - 0.5*df['sensor_2'] + 3*df['sensor_3'] + np.random.normal(0, 2, n)

# Introduce Missing values
df.loc[np.random.choice(n, 50, replace=False), 'sensor_1'] = np.nan
df.loc[np.random.choice(n, 50, replace=False), 'sensor_2'] = np.nan

# Introduce Outliers
df.loc[np.random.choice(n, 20, replace=False), 'sensor_3'] = np.random.uniform(50, 100, 20)

df.to_csv('/home/user/sensor_data.csv', index=False)
"

    chmod -R 777 /home/user
