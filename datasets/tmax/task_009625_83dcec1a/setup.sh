#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd

np.random.seed(123)
X = np.random.randn(1000, 10)
# f1, f2, f3 have strong relationships. Others are noise.
y = 3*X[:, 0] - 2*X[:, 1] + 1.5*X[:, 2] + 0.3*X[:, 3] + np.random.randn(1000)

df = pd.DataFrame(X, columns=[f"f{i+1}" for i in range(10)])
df["target"] = y
df.to_csv("/home/user/dataset.csv", index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
