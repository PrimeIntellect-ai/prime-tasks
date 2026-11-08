#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy pyarrow

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup.py
import pandas as pd
import numpy as np

users_data = {
    'user_id': [1, 2, 3, 4, 5, 6, 7],
    'account_tier': [1, 2, 1, 3, 2, 1, 3]
}

events_data = {
    'user_id': [2, 3, 4, 5, 8, 9],
    'event_count': [10.0, 5.0, 20.0, 1.0, 100.0, 50.0],
    'event_value': [100.0, 50.0, 200.0, 10.0, 500.0, 250.0]
}

pd.DataFrame(users_data).to_csv('/home/user/users.csv', index=False)
pd.DataFrame(events_data).to_csv('/home/user/events.csv', index=False)
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
