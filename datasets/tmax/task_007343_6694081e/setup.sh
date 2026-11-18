#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/setup_data.py
import pandas as pd
import numpy as np

np.random.seed(10)
n = 1000
ids = np.arange(n)
sensor_A = np.random.normal(10, 2, n)
sensor_B = np.random.normal(5, 1, n)
sensor_C = np.random.normal(0, 5, n)

# introduce missing values
sensor_A[np.random.choice(n, 50, replace=False)] = np.nan
sensor_B[np.random.choice(n, 50, replace=False)] = np.nan

# calculate target with true values
target = 2.5 * np.nan_to_num(sensor_A, nan=10) + 1.2 * np.nan_to_num(sensor_B, nan=5) - 0.5 * sensor_C + np.random.normal(0, 1, n)

df_meas = pd.DataFrame({'id': ids, 'sensor_A': sensor_A, 'sensor_B': sensor_B, 'sensor_C': sensor_C})
df_targ = pd.DataFrame({'id': ids, 'target': target})

df_meas.to_csv('/home/user/data/measurements.csv', index=False)
df_targ.to_csv('/home/user/data/targets.csv', index=False)
EOF

    python3 /home/user/setup_data.py

    cat << 'EOF' > /home/user/model.py
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.linear_model import Ridge
from sklearn.metrics import r2_score
import json

df_meas = pd.read_csv('/home/user/data/measurements.csv')
df_targ = pd.read_csv('/home/user/data/targets.csv')

df = pd.merge(df_meas, df_targ, on='id')
df['sensor_ratio'] = df['sensor_A'] / df['sensor_B']

# Data Leakage!
df = df.fillna(df.mean())
for col in ['sensor_A', 'sensor_B', 'sensor_C', 'sensor_ratio']:
    df[col] = (df[col] - df[col].mean()) / df[col].std(ddof=0)

X = df[['sensor_A', 'sensor_B', 'sensor_C', 'sensor_ratio']]
y = df['target']

X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

model = Ridge(alpha=1.0)
model.fit(X_train, y_train)
preds = model.predict(X_test)
r2 = r2_score(y_test, preds)

print("R2:", r2)
EOF

    chown -R user:user /home/user/data
    chown user:user /home/user/model.py /home/user/setup_data.py
    chmod -R 777 /home/user
