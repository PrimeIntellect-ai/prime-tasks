#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libeigen3-dev
    pip3 install pytest numpy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import pandas as pd

np.random.seed(42)
N = 100
X1 = np.random.normal(0, 1, N)
X2 = X1 + np.random.normal(0, 0.05, N)
X3 = np.random.normal(0, 1, N)

X = np.column_stack((X1, X2, X3))
true_beta = np.array([2.0, -1.5, 0.5])
Y = X.dot(true_beta) + np.random.normal(0, 1.0, N)

df = pd.DataFrame({'X1': X1, 'X2': X2, 'X3': X3, 'Y': Y})
df.to_csv('/home/user/data.csv', index=False, header=False)

alpha = 10.0
posterior_cov = np.linalg.inv(X.T.dot(X) + alpha * np.eye(3))
posterior_mean = posterior_cov.dot(X.T).dot(Y)

with open('/tmp/theoretical_mean.txt', 'w') as f:
    f.write(','.join(map(str, posterior_mean)))
EOF

    python3 /tmp/setup.py

    chmod -R 777 /home/user
