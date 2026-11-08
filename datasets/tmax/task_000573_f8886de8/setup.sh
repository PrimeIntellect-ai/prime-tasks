#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas pyarrow scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import pandas as pd
import numpy as np
from sklearn.datasets import make_classification

X, y = make_classification(n_samples=10000, n_features=50, random_state=42)
train_X, train_y = X[:8000], y[:8000]
test_X, test_y = X[8000:], y[8000:]

train_df = pd.DataFrame(train_X, columns=[f'f{i}' for i in range(50)])
train_df['label'] = train_y
train_df.to_parquet('/home/user/train.parquet')

test_df = pd.DataFrame(test_X, columns=[f'f{i}' for i in range(50)])
test_df['label'] = test_y
test_df.to_parquet('/home/user/test.parquet')
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
