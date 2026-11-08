#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/create_data.py
import numpy as np
import pandas as pd

np.random.seed(42)
N = 200

# Create highly collinear features
x1 = np.random.normal(0, 1, N)
x2 = 2.0 * x1 + np.random.normal(0, 0.1, N)
x3 = -1.5 * x1 + np.random.normal(0, 0.1, N)

# y depends on a combination, but true coefficients are hard to isolate without regularization
y = 1.0 * x1 + 0.5 * x2 - 0.5 * x3 + np.random.normal(0, 0.5, N)

df = pd.DataFrame({'x1': x1, 'x2': x2, 'x3': x3, 'y': y})
df.to_csv('/home/user/experiment.csv', index=False)
EOF

    python3 /home/user/create_data.py

    chmod -R 777 /home/user
