#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest pandas numpy scipy

    mkdir -p /home/user

    python3 -c "
import os
import pandas as pd
import numpy as np

np.random.seed(42)
n_a = 500
n_b = 520

group_a = pd.DataFrame({
    'user_id': range(n_a),
    'group': 'A',
    'session_duration': np.random.normal(120, 30, n_a),
    'items_viewed': np.random.poisson(4, n_a)
})

group_b = pd.DataFrame({
    'user_id': range(n_a, n_a + n_b),
    'group': 'B',
    'session_duration': np.random.normal(130, 35, n_b),
    'items_viewed': np.random.poisson(5, n_b)
})

df = pd.concat([group_a, group_b])
df.to_csv('/home/user/data.csv', index=False)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
