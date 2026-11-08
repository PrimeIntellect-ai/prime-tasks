#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas pyarrow numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import pandas as pd

np.random.seed(42)
n_rows = 50000

df = pd.DataFrame({
    'id': range(1, n_rows + 1),
    'f1': np.random.normal(100, 15, n_rows),
    'f2': np.random.uniform(-50, 50, n_rows),
    'f3': np.random.exponential(5, n_rows)
})

df.to_csv('/home/user/raw_data.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
