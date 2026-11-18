#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest pandas scikit-learn numpy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/experiment/artifacts

    cat << 'EOF' > /tmp/setup.py
import os
import pandas as pd
from sklearn.datasets import make_classification

os.makedirs('/home/user/experiment/artifacts', exist_ok=True)

X, y = make_classification(n_samples=1000, n_features=20, n_informative=15, n_redundant=5, random_state=42)
df = pd.DataFrame(X, columns=[f'feat_{i}' for i in range(20)])
df['target'] = y
df.to_csv('/home/user/experiment/data.csv', index=False)

pipeline_code = """import pandas as pd
import numpy as np
import json
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import accuracy_score

def run_experiment():
    df = pd.read_csv('/home/user/experiment/data.csv')
    X = df.drop('target', axis=1)
    y = df['target']

    # THE LEAK: Scaling the entire dataset before splitting
    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X)

    X_train, X_test, y_train, y_test = train_test_split(X_scaled, y, test_size=0.2, random_state=42)

    model = RandomForestClassifier(random_state=42)
    model.fit(X_train, y_train)
    preds = model.predict(X_test)

    acc = accuracy_score(y_test, preds)
    print(f"Accuracy: {acc}")

if __name__ == '__main__':
    run_experiment()
"""

with open('/home/user/experiment/pipeline.py', 'w') as f:
    f.write(pipeline_code)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
