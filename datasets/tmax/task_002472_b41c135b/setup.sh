#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libarmadillo-dev nlohmann-json3-dev
    pip3 install pytest pandas numpy scipy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/gen_data.py
import pandas as pd
import numpy as np
import scipy.stats as stats
from sklearn.linear_model import LinearRegression

np.random.seed(42)
n = 50
group = np.random.choice([0, 1], size=n)
feature_x = np.random.randint(10, 100, size=n).astype(float)

missing_indices = np.random.choice(n, size=8, replace=False)
feature_x[missing_indices] = np.nan

target_y = 2.5 * np.nan_to_num(feature_x, nan=50) + 15.0 * group + np.random.normal(0, 10, size=n)

with open("/home/user/dataset.csv", "w") as f:
    f.write("group,feature_x,target_y\n")
    for g, x, y in zip(group, feature_x, target_y):
        x_str = "" if np.isnan(x) else str(int(x))
        f.write(f"{g},{x_str},{y:.4f}\n")
EOF

    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    chmod -R 777 /home/user
