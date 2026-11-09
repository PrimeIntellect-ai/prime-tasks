#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scipy

    mkdir -p /home/user
    cat << 'EOF' > /home/user/setup_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
users = pd.DataFrame({'user_id': range(1, 201), 'group': np.random.choice(['A', 'B'], 200)})

events = []
for _, row in users.iterrows():
    # Every user has some views and clicks
    events.append({'user_id': row['user_id'], 'event_type': 'view', 'value': 0.0, 'group': row['group']})
    events.append({'user_id': row['user_id'], 'event_type': 'click', 'value': 0.0, 'group': row['group']})

    # Random purchases
    num_purchases = np.random.poisson(0.8) if row['group'] == 'A' else np.random.poisson(1.2)
    for _ in range(num_purchases):
        val = np.random.normal(15, 3) if row['group'] == 'A' else np.random.normal(16, 4)
        events.append({'user_id': row['user_id'], 'event_type': 'purchase', 'value': max(0.5, val), 'group': row['group']})

# Shuffle events
df = pd.DataFrame(events).sample(frac=1, random_state=42).reset_index(drop=True)
df.to_csv('/home/user/events.csv', index=False)
EOF

    python3 /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
