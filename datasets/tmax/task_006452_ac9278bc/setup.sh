#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np
import os

os.makedirs('/home/user', exist_ok=True)

data = {
    'user_id': [1, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 5, 5, 5, 5],
    'timestamp': [
        '2023-01-01 10:00:00', '2023-01-01 10:05:00', '2023-01-01 10:10:00', '2023-01-01 10:15:00',
        '2023-01-01 09:00:00', '2023-01-01 09:30:00', '2023-01-01 10:00:00',
        '2023-01-02 11:00:00', '2023-01-02 11:01:00', '2023-01-02 11:02:00',
        '2023-01-03 14:00:00', '2023-01-03 15:00:00',
        '2023-01-04 16:00:00', '2023-01-04 16:05:00', '2023-01-04 16:10:00', '2023-01-04 16:15:00'
    ],
    'event_type': [
        'login', 'view', np.nan, 'click',
        'login', 'purchase', 'logout',
        'view', 'view', 'click',
        np.nan, np.nan,
        'login', 'view', 'purchase', 'logout'
    ]
}

df = pd.DataFrame(data)
# Shuffle a bit to test sorting
df = df.sample(frac=1, random_state=42).reset_index(drop=True)
df.to_csv('/home/user/raw_events.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
