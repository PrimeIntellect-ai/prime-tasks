#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    python3 -c "
import pandas as pd
import numpy as np

np.random.seed(42)
n_samples = 100

X0 = np.random.normal(2, 2.5, (50, 3))
X1 = np.random.normal(5, 2.5, (50, 3))

X = np.vstack([X0, X1])
y = np.hstack([np.zeros(50), np.ones(50)]).astype(int)

ids = np.arange(1, 101)

indices = np.random.permutation(100)
X = X[indices]
y = y[indices]
ids = ids[indices]

idx_features = np.random.permutation(100)
idx_labels = np.random.permutation(100)

features_df = pd.DataFrame({
    'id': ids[idx_features],
    'f1': X[idx_features, 0],
    'f2': X[idx_features, 1],
    'f3': X[idx_features, 2]
})

labels_df = pd.DataFrame({
    'id': ids[idx_labels],
    'label': y[idx_labels]
})

features_df.to_csv('/home/user/features.csv', index=False)
labels_df.to_csv('/home/user/labels.csv', index=False)
"

    chmod -R 777 /home/user
