#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scipy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_data.py
import pandas as pd
import numpy as np

np.random.seed(123)
n = 500
amounts = np.random.normal(155, 30, n)
amounts[10] = -50
amounts[20] = np.nan
df = pd.DataFrame({'id': range(n), 'amount': amounts})
df.to_csv('/home/user/transactions.csv', index=False)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
