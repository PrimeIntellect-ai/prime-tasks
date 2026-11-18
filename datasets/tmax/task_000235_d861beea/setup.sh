#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc liblapacke-dev
    pip3 install pytest numpy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd

# Set random seed for reproducibility of the dataset
np.random.seed(42)

N = 1000
timestamps = np.arange(N)
cpu_util = np.random.uniform(10, 90, N)
mem_util = np.random.uniform(20, 80, N)
io_wait = np.random.uniform(0, 15, N)

# True coefficients
# b0 = 12.5, b1 = 0.45, b2 = 0.15, b3 = 1.80
y = 12.5 + 0.45 * cpu_util + 0.15 * mem_util + 1.80 * io_wait + np.random.normal(0, 1.0, N)

df = pd.DataFrame({
    'timestamp': timestamps,
    'cpu_util': cpu_util,
    'mem_util': mem_util,
    'io_wait': io_wait,
    'response_time': y
})

df.to_csv('/home/user/perf_data.csv', index=False)
EOF

    python3 /tmp/generate_data.py

    chmod -R 777 /home/user
