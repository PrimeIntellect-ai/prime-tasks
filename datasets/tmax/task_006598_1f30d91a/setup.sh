#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sudo build-essential
    pip3 install pytest numpy pandas

    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import pandas as pd

np.random.seed(42)
X = np.random.randn(100, 10)
W = np.random.randn(10, 3)

pd.DataFrame(X).to_csv('/home/user/X.csv', header=False, index=False)
pd.DataFrame(W).to_csv('/home/user/W.csv', header=False, index=False)

# Ground truth calculations
Y = X @ W
pd.DataFrame(Y).to_csv('/home/user/expected_Y.csv', header=False, index=False, float_format='%.4f')

y0 = Y[:, 0]
mean_y0 = np.mean(y0)
std_y0 = np.std(y0, ddof=1)
margin = 1.96 * (std_y0 / np.sqrt(100))
lower = mean_y0 - margin
upper = mean_y0 + margin

with open('/home/user/expected_ci.txt', 'w') as f:
    f.write(f"Lower: {lower:.4f}, Upper: {upper:.4f}\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
