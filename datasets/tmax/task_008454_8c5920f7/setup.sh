#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scipy matplotlib

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import pandas as pd

np.random.seed(42)
n_events = 1500
inter_arrivals = np.random.exponential(scale=2.5, size=n_events)
timestamps = np.cumsum(inter_arrivals)

df = pd.DataFrame({'timestamp': timestamps})
df.to_csv('/home/user/detector_events.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
