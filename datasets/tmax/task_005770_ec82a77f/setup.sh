#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
import numpy as np

np.random.seed(10)
n = 2000
data = {
    'user_id': ['U' + str(i).zfill(4) for i in range(n)],
    'session_duration_sec': np.random.normal(120, 40, n),
    'clicks': np.random.poisson(5, n),
    'converted': np.random.choice([0, 1], n, p=[0.8, 0.2])
}
df = pd.DataFrame(data)
# Add some schema violations
df.loc[10:20, 'session_duration_sec'] = -5
df.loc[30:40, 'clicks'] = -1
df.loc[50:60, 'user_id'] = np.nan

# Make converted=1 have higher clicks
df.loc[df['converted'] == 1, 'clicks'] += 3

df.to_csv('/home/user/raw_data.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
