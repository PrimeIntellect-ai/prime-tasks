#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --no-cache-dir pytest numpy pandas scikit-learn

    mkdir -p /home/user

    # Generate the initial state
    python3 -c "
import numpy as np
import pandas as pd
import os

os.makedirs('/home/user', exist_ok=True)

np.random.seed(42)
A = np.random.randn(1000)
B = A * 0.5 + np.random.randn(1000) * 0.5
C = np.random.randn(1000)
target = A * 1.5 - B * 0.8 + C * 2.0 + np.random.randn(1000) * 0.2

df = pd.DataFrame({'A': A, 'B': B, 'C': C, 'target': target})
df.to_csv('/home/user/data.csv', index=False)

with open('/home/user/train.py', 'w') as f:
    f.write('''import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import Ridge
from sklearn.metrics import mean_squared_error

df = pd.read_csv(\"data.csv\")
X = df.drop(\"target\", axis=1)
y = df[\"target\"]

scaler = StandardScaler()
X_scaled = scaler.fit_transform(X) # LEAKAGE

X_train, X_test, y_train, y_test = train_test_split(X_scaled, y, test_size=0.2, random_state=42)

model = Ridge()
model.fit(X_train, y_train)
print(\"Leaked MSE:\", mean_squared_error(y_test, model.predict(X_test)))
''')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
