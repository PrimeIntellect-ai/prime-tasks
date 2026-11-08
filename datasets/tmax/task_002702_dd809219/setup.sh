#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scipy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_data.py
import pandas as pd
import numpy as np

# Reference data
ref_data = {
    'base': ['A', 'C', 'G', 'T'],
    'mean_current': [15.0, 25.0, 35.0, 45.0],
    'std_dev': [1.5, 2.0, 1.8, 2.2]
}
pd.DataFrame(ref_data).to_csv('/home/user/reference.csv', index=False)

# Signal data
np.random.seed(99)
true_bases = ['A', 'G', 'C', 'T', 'A', 'A', 'T', 'G', 'C', 'C']
events = []
event_id = 1

for b in true_bases:
    idx = ref_data['base'].index(b)
    mean = ref_data['mean_current'][idx]
    std = ref_data['std_dev'][idx]

    # Generate 5 normal points
    vals = np.random.normal(mean, std, 5).tolist()
    # Add noise spikes (min/max)
    vals.append(mean + 10.0) # max
    vals.append(mean - 10.0) # min
    np.random.shuffle(vals)

    for v in vals:
        events.append({'event_id': event_id, 'current_val': v})
    event_id += 1

pd.DataFrame(events).to_csv('/home/user/signal.csv', index=False)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
