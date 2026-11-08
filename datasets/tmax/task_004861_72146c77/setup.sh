#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data_gen.py
import pandas as pd
import numpy as np

np.random.seed(123)
user_ids = np.arange(1, 1001)
regions = np.random.choice(['North', 'South', 'East', 'West'], size=1000)
users = pd.DataFrame({'user_id': user_ids, 'region': regions})

variants = np.random.choice(['Control', 'Treatment'], size=1000)
exposures = pd.DataFrame({'user_id': user_ids, 'variant': variants})

buyers = np.random.choice(user_ids, size=600, replace=True)
amounts = np.random.uniform(10, 100, size=600)
purchases = pd.DataFrame({'purchase_id': np.arange(1, 601), 'user_id': buyers, 'amount': amounts})

users.to_csv('/home/user/data/users.csv', index=False)
exposures.to_csv('/home/user/data/exposures.csv', index=False)
purchases.to_csv('/home/user/data/purchases.csv', index=False)
EOF
    python3 /home/user/data_gen.py
    rm /home/user/data_gen.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
