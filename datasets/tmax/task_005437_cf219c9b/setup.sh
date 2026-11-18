#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn numpy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    python3 -c "
import pandas as pd
from sklearn.datasets import make_regression
import os

X, y = make_regression(n_samples=1000, n_features=50, n_informative=10, noise=0.1, random_state=42)
df = pd.DataFrame(X, columns=[f'f{i}' for i in range(50)])
df['target'] = y

df.to_csv('/home/user/sensor_data.csv', index=False)
"

    chmod -R 777 /home/user
