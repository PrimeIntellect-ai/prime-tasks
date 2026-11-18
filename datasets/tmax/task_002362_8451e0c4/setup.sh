#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scipy numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_csv.py
import numpy as np
import pandas as pd
import os

np.random.seed(42)
functions = ['init', 'compute', 'communicate', 'finalize']
data = []
for f in functions:
    if f == 'init':
        slope, intercept = 0.5, 10
        shape, scale = 0.5, 2.0
    elif f == 'compute':
        slope, intercept = 2.0, 50
        shape, scale = 0.2, 5.0
    elif f == 'communicate':
        slope, intercept = 1.2, 20
        shape, scale = 0.8, 1.5
    elif f == 'finalize':
        slope, intercept = 0.1, 5
        shape, scale = 0.3, 1.0

    for size in range(100, 1100, 100):
        # Generate 100 samples per size
        for _ in range(100):
            noise = np.random.lognormal(mean=np.log(scale), sigma=shape)
            time = slope * size + intercept + noise
            data.append([f, size, time])

df = pd.DataFrame(data, columns=['Function', 'DataSize', 'ExecutionTime'])
df.to_csv('/home/user/perf_logs.csv', index=False)
EOF

    python3 /tmp/generate_csv.py
    rm /tmp/generate_csv.py

    chmod -R 777 /home/user
