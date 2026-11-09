#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas numpy scikit-learn joblib

useradd -m -s /bin/bash user || true

mkdir -p /home/user/data /home/user/src /home/user/artifacts

cat << 'EOF' > /home/user/data/generate.py
import pandas as pd
import numpy as np

np.random.seed(42)
n = 1000
X1 = np.random.normal(0, 1, n)
X2 = np.random.normal(0, 1, n)
X3 = X1 + np.random.normal(0, 0.1, n) # Highly correlated with X1
X4 = np.random.normal(0, 1, n)
y = 2*X1 + 3*X2 + 0.5*X4 + np.random.normal(0, 1, n)

df = pd.DataFrame({'f1': X1, 'f2': X2, 'f3': X3, 'f4': X4, 'target': y})
df.to_csv('/home/user/data/dataset.csv', index=False)
EOF

python3 /home/user/data/generate.py

cat << 'EOF' > /home/user/src/experiment.py
import pandas as pd
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split
from sklearn.linear_model import Ridge
from sklearn.metrics import mean_squared_error

df = pd.read_csv('/home/user/data/dataset.csv')
X = df.drop('target', axis=1)
y = df['target']

# BUG: Data leak
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)

X_train, X_test, y_train, y_test = train_test_split(X_scaled, y, test_size=0.2, random_state=42)

model = Ridge()
model.fit(X_train, y_train)
preds = model.predict(X_test)
print("MSE:", mean_squared_error(y_test, preds))
EOF

chmod -R 777 /home/user
