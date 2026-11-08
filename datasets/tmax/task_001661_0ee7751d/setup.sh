#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np
import json
import os

os.makedirs('/home/user', exist_ok=True)

# Generate raw data
np.random.seed(10)
n = 100
df = pd.DataFrame({
    'id': range(1, n+1),
    'var_a': np.random.uniform(-1, 1, n),
    'var_b': np.random.uniform(0, 2, n),
    'category_c': np.random.choice(['X', 'Y', 'Z'], n),
    'target': np.random.randint(0, 2, n)
})
df.to_csv('/home/user/raw_data.csv', index=False)

weights = {"intercept": 0.5, "w_f1": 1.2, "w_f2": -0.3, "w_cat": 0.8}
with open('/home/user/model_weights.json', 'w') as f:
    json.dump(weights, f)
EOF
    python3 /tmp/setup.py

    chmod -R 777 /home/user
