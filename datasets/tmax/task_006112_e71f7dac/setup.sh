#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas

    useradd -m -s /bin/bash user || true

    # Generate the nanopore signal dataset
    cat << 'EOF' > /tmp/setup_task.py
import os
import numpy as np
import pandas as pd

def setup_task():
    np.random.seed(123)
    n_events = 200
    open_dwells = np.random.exponential(scale=5.0, size=n_events) # ms
    blocked_dwells = np.random.exponential(scale=2.0, size=n_events) # ms

    dt = 0.1 # ms
    time_arr = []
    current_arr = []
    t = 0.0

    for i in range(n_events):
        # Open
        n_pts = int(max(1, open_dwells[i] / dt))
        time_arr.extend([t + j*dt for j in range(n_pts)])
        current_arr.extend(np.random.normal(100, 10, n_pts))
        t += n_pts * dt

        # Blocked
        n_pts = int(max(1, blocked_dwells[i] / dt))
        time_arr.extend([t + j*dt for j in range(n_pts)])
        current_arr.extend(np.random.normal(50, 10, n_pts))
        t += n_pts * dt

    df = pd.DataFrame({'time': time_arr, 'current': current_arr})
    df.to_csv('/home/user/nanopore_signal.csv', index=False)

if __name__ == '__main__':
    setup_task()
EOF

    python3 /tmp/setup_task.py
    rm /tmp/setup_task.py

    chmod -R 777 /home/user
