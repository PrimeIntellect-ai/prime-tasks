#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn numpy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data/

    cat << 'EOF' > /home/user/setup_data.py
import pandas as pd
import numpy as np

np.random.seed(42)

# Dataset A: id 1 to 80
id_a = np.arange(1, 81)
f1 = np.random.randint(10, 50, size=80)
f2 = np.random.randint(100, 200, size=80)
f3 = np.random.randint(0, 10, size=80)
df_a = pd.DataFrame({'id': id_a, 'f1': f1, 'f2': f2, 'f3': f3})

# Dataset B: id 60 to 120
id_b = np.arange(60, 121)
f4 = np.random.randint(500, 1000, size=61)
f5 = np.random.randint(-50, 50, size=61)
df_b = pd.DataFrame({'id': id_b, 'f4': f4, 'f5': f5})

df_a.to_csv('/home/user/data/dataset_A.csv', index=False)
df_b.to_csv('/home/user/data/dataset_B.csv', index=False)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user
