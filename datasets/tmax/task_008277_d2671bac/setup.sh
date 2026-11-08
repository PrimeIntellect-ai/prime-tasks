#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --no-cache-dir pytest pandas numpy scikit-learn

    mkdir -p /home/user
    cat << 'EOF' > /home/user/make_data.py
import pandas as pd
import numpy as np
from sklearn.datasets import make_classification

X, y = make_classification(n_samples=150, n_features=3, n_informative=2, n_redundant=0, random_state=42, class_sep=0.8)
df = pd.DataFrame(X, columns=['temperature', 'pressure', 'humidity'])
df['outcome'] = y
df.to_csv('/home/user/experiments.csv', index=False)
EOF
    python3 /home/user/make_data.py
    rm /home/user/make_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
