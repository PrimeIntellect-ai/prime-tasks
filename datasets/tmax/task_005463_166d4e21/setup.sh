#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    mkdir -p /home/user/experiments

    cat << 'EOF' > /home/user/setup_data.py
import pandas as pd
import numpy as np

def create_run(run_id, n, acc, mean_conf):
    y_true = np.random.randint(0, 2, n)
    y_pred = y_true.copy()

    # Flip labels to achieve target accuracy
    num_flip = int(n * (1 - acc))
    flip_indices = np.random.choice(n, num_flip, replace=False)
    y_pred[flip_indices] = 1 - y_pred[flip_indices]

    # Generate confidence
    confidence = np.full(n, mean_conf)

    return pd.DataFrame({
        'run_id': [run_id]*n,
        'y_true': y_true,
        'y_pred': y_pred,
        'confidence': confidence
    })

np.random.seed(42)

df_a = create_run('run_A', 100, 0.80, 0.82)
df_b = create_run('run_B', 100, 0.50, 0.80)
df_c = create_run('run_C', 100, 0.90, 0.60)
df_d = create_run('run_D', 100, 0.70, 0.75)

# Split into two files
pd.concat([df_a, df_b]).to_csv('/home/user/experiments/exp_01.csv', index=False)
pd.concat([df_c, df_d]).to_csv('/home/user/experiments/exp_02.csv', index=False)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
