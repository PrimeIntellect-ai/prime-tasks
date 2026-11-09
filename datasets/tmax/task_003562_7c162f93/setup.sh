#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/create_dataset.py
import pandas as pd
import numpy as np

np.random.seed(42)
data = {
    'feature1': np.random.normal(10, 5, 100),
    'feature2': np.random.normal(20, 2, 100),
    'target': np.random.randint(0, 2, 100)
}
df = pd.DataFrame(data)
df.to_csv('/home/user/dataset.csv', index=False)
EOF

    python3 /home/user/create_dataset.py
    rm /home/user/create_dataset.py

    cat << 'EOF' > /home/user/clean_data.py
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
import json

df = pd.read_csv('/home/user/dataset.csv')
X = df[['feature1', 'feature2']]
y = df['target']

# BUG: Data leakage!
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)

X_train, X_test, y_train, y_test = train_test_split(X_scaled, y, test_size=0.2, random_state=42)

test_feature1_mean = X_test[:, 0].mean()

with open('/home/user/metrics.json', 'w') as f:
    json.dump({'test_feature1_mean': float(test_feature1_mean)}, f)
EOF

    chmod -R 777 /home/user
