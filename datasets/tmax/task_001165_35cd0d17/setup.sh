#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn numpy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import json
import numpy as np
import pandas as pd

os.makedirs('/home/user', exist_ok=True)

schema = {
    "f1": {"type": "float"},
    "f2": {"type": "float", "min_value": -10.0},
    "cat": {"type": "integer", "allowed_values": [0, 1, 2]},
    "target": {"type": "float"}
}
with open('/home/user/schema.json', 'w') as f:
    json.dump(schema, f, indent=2)

pipeline_spec = {
    "steps": ["StandardScaler", "Ridge"],
    "param_grid": {
        "Ridge__alpha": [0.01, 0.1, 1.0, 10.0, 100.0]
    }
}
with open('/home/user/pipeline_spec.json', 'w') as f:
    json.dump(pipeline_spec, f, indent=2)

np.random.seed(42)
n_samples = 200
f1 = np.random.normal(0, 1, n_samples)
f2 = np.random.normal(5, 5, n_samples)
cat = np.random.choice([0, 1, 2], n_samples)
target = 3.0 * f1 - 1.5 * f2 + 2.0 * cat + np.random.normal(0, 0.5, n_samples)

df = pd.DataFrame({'f1': f1, 'f2': f2, 'cat': cat, 'target': target})

df.loc[5, 'f1'] = 'invalid_float'
df.loc[10, 'f2'] = -15.0
df.loc[12, 'f2'] = -10.01
df.loc[20, 'cat'] = 3
df.loc[30, 'target'] = np.nan

df.to_csv('/home/user/raw_data.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
