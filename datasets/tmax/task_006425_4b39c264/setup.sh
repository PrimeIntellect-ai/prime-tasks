#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import pandas as pd
import os

np.random.seed(10)
mean = [1.0, -1.0, 2.5]
cov = [[1.0, 0.4, 0.1],
       [0.4, 1.5, -0.3],
       [0.1, -0.3, 2.0]]
data = np.random.multivariate_normal(mean, cov, 100)
df = pd.DataFrame(data, columns=['A', 'B', 'C'])
df.to_csv('/home/user/original_data.csv', index=False)
EOF

    python3 /tmp/setup.py

    chmod -R 777 /home/user
