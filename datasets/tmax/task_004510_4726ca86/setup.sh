#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas pyarrow scikit-learn numpy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_data.py
import pandas as pd
import numpy as np

np.random.seed(42)

# Generate training data
n_train = 1000
f1_train = np.random.uniform(0.1, 10, n_train)
f2_train = np.random.normal(0, 1, n_train)
f3_train = np.random.uniform(0, 99, n_train)
z = 0.5 * f1_train - 1.2 * f2_train + 0.05 * f3_train - 2.0
p = 1 / (1 + np.exp(-z))
label_train = np.random.binomial(1, p)

train_df = pd.DataFrame({'f1': f1_train, 'f2': f2_train, 'f3': f3_train, 'label': label_train})
train_df.to_parquet('/home/user/train.parquet')

# Generate incoming data
n_inc = 100
f1_inc = np.random.uniform(0.1, 10, n_inc)
f2_inc = np.random.normal(0, 1, n_inc)
f3_inc = np.random.uniform(0, 99, n_inc)

# Inject schema violations
f1_inc[5] = -1.0 # f1 <= 0 violation
f1_inc[12] = 0.0 # f1 <= 0 violation
f3_inc[45] = 105.0 # f3 >= 100 violation
f3_inc[88] = 100.0 # f3 >= 100 violation

inc_df = pd.DataFrame({'id': range(n_inc), 'f1': f1_inc, 'f2': f2_inc, 'f3': f3_inc})
inc_df.to_parquet('/home/user/incoming.parquet')
EOF

    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    chmod -R 777 /home/user
