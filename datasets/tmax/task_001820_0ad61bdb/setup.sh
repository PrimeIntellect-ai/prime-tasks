#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    mkdir -p /home/user/datasets

    python3 -c "
import os
import pandas as pd
import numpy as np

os.makedirs('/home/user/datasets', exist_ok=True)

np.random.seed(42)

def make_data(filename, n_rows):
    groups = np.random.choice(['Control', 'Treatment_1', 'Treatment_2', 'Treatment_3'], size=n_rows)
    trials = np.random.randint(10, 50, size=n_rows)
    successes = np.array([np.random.randint(0, t+1) for t in trials])
    f1 = np.random.normal(10, 2, size=n_rows)
    f2 = np.random.normal(5, 1, size=n_rows)
    f3 = f1 * 0.5 + f2 * 0.2 + np.random.normal(0, 0.5, size=n_rows)

    df = pd.DataFrame({
        'experiment_id': [f'exp_{np.random.randint(1000, 9999)}' for _ in range(n_rows)],
        'group': groups,
        'trials': trials,
        'successes': successes,
        'f1': f1,
        'f2': f2,
        'f3': f3
    })
    df.to_csv(f'/home/user/datasets/{filename}', index=False)

make_data('batch_1.csv', 150)
make_data('batch_2.csv', 200)
make_data('batch_3.csv', 120)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
