#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest numpy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd

np.random.seed(42)
x = np.random.uniform(0, 10, 200)
# True parameters: alpha = 2.5, beta = 1.3
y = 2.5 + 1.3 * x + np.random.normal(0, 1.0, 200)

df = pd.DataFrame({'X': x, 'Y': y})
df.to_csv('/home/user/data.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
