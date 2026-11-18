#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest numpy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate_data.py
import numpy as np
import pandas as pd

np.random.seed(42)
N_vals = np.random.randint(100, 10000, 200)
errors = np.sqrt(N_vals) * 1e-16 * np.random.lognormal(mean=0, sigma=0.5, size=200)
df = pd.DataFrame({'N': N_vals, 'error': errors})
df.to_csv('/home/user/discrepancies.csv', index=False)
EOF

    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    chmod -R 777 /home/user
