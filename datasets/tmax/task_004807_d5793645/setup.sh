#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    python3 -c "
import os
import pandas as pd
import numpy as np

os.makedirs('/home/user', exist_ok=True)

np.random.seed(123)
n = 1000
feature_A = np.random.randint(10, 100, size=n).astype(object)
missing_indices = np.random.choice(n, size=50, replace=False)
feature_A[missing_indices] = 'MISSING'

feature_B = np.random.randint(0, 1000, size=n)
label = np.random.randint(0, 2, size=n)

df = pd.DataFrame({
    'feature_A': feature_A,
    'feature_B': feature_B,
    'label': label
})

df.to_csv('/home/user/dataset.csv', index=False)
"

    chmod -R 777 /home/user
