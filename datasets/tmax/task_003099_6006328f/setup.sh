#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas numpy scikit-learn

mkdir -p /home/user

cat << 'EOF' > /home/user/setup_data.py
import pandas as pd
import numpy as np

np.random.seed(42)

ids_A = np.arange(1, 10001)
data_A = pd.DataFrame(np.random.randint(0, 1000, size=(10000, 50)), columns=[f'A_{i}' for i in range(1, 51)])
data_A.insert(0, 'id', ids_A)

ids_B = np.arange(1, 9001)
data_B = pd.DataFrame(np.random.randint(0, 1000, size=(9000, 50)), columns=[f'B_{i}' for i in range(1, 51)])
data_B.insert(0, 'id', ids_B)

data_A.to_csv('/home/user/data_A.csv', index=False)
data_B.to_csv('/home/user/data_B.csv', index=False)
EOF

python3 /home/user/setup_data.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
