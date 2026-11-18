#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create transactions.csv
    cat << 'EOF' > transactions.csv
tx_id,user_id,amount,test_group
1,101,55.5,A
2,102,150.0,B
3,103,200.5,A
4,104,15.0,B
5,105,99.9,A
6,106,350.0,B
7,107,45.0,A
8,108,12.5,B
9,109,1000.0,A
10,110,60.0,B
EOF

    # Create user_metadata.csv
    cat << 'EOF' > user_metadata.csv
user_id,age_score
101,25
102,40
104,22
105,50
106,33
108,28
110,45
EOF

    # Create buggy etl.py
    cat << 'EOF' > etl.py
import pandas as pd

tx = pd.read_csv('transactions.csv')
meta = pd.read_csv('user_metadata.csv')

# Buggy merge: introduces NaNs and converts to float silently
df = tx.merge(meta, on='user_id', how='left')
df.to_csv('processed_data.csv', index=False)
EOF

    # Create a small python script to generate the model.pkl
    cat << 'EOF' > setup_model.py
import pandas as pd
import pickle
from sklearn.ensemble import IsolationForest
import numpy as np

# Training dummy model
X_train = np.array([
    [50.0, 20], [60.0, 25], [45.0, 22], [55.0, 30], [200.0, 50],
    [10.0, 18], [15.0, 20], [100.0, 40], [120.0, 35], [900.0, 80]
])
model = IsolationForest(n_estimators=100, random_state=42)
model.fit(X_train)

with open('anomaly_model.pkl', 'wb') as f:
    pickle.dump(model, f)
EOF

    # Run setup to generate model
    python3 -m venv /tmp/setup_venv
    /tmp/setup_venv/bin/pip install scikit-learn pandas numpy
    /tmp/setup_venv/bin/python setup_model.py
    rm -rf /tmp/setup_venv setup_model.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
