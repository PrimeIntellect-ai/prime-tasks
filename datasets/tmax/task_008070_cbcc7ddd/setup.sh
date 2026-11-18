#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn pyarrow

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import random
import pandas as pd
import numpy as np

os.makedirs('/home/user/astro_data', exist_ok=True)
np.random.seed(10)
random.seed(10)

n_rows = 5000
ids = list(range(1, n_rows + 1))
masses = np.random.lognormal(mean=1.0, sigma=0.5, size=n_rows)
orbital_periods = np.random.uniform(1, 300, size=n_rows)
statuses = np.random.choice(["confirmed", "false_positive"], size=n_rows, p=[0.4, 0.6])

# Radii depends on mass + noise
radii = masses * 1.5 + np.random.normal(0, 0.5, size=n_rows)
radii = np.where(radii < 0.1, 0.1, radii)

df = pd.DataFrame({
    'id': ids,
    'mass': masses,
    'radius': radii,
    'orbital_period': orbital_periods,
    'status': statuses
})

# Inject schema violations
# 1. Negative mass
df.loc[10:20, 'mass'] = -1.0
# 2. String in radius
df.loc[30:40, 'radius'] = 'unknown'
# 3. Invalid status
df.loc[50:60, 'status'] = 'candidate'
# 4. Negative orbital period
df.loc[70:80, 'orbital_period'] = -10.5

df.to_csv('/home/user/astro_data/raw_candidates.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
