#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scikit-learn scipy

    mkdir -p /home/user/artifacts
    cat << 'EOF' > /home/user/setup_data.py
import numpy as np
import pandas as pd

np.random.seed(10)
# 100 samples, 50 features each
alpha = np.random.normal(0, 1, (100, 50))
beta = np.random.normal(0.2, 1.1, (100, 50))

pd.DataFrame(alpha).to_csv('/home/user/artifacts/run_alpha.csv', index=False, header=False)
pd.DataFrame(beta).to_csv('/home/user/artifacts/run_beta.csv', index=False, header=False)
EOF
    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
