#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_data.py
import numpy as np
import pandas as pd

np.random.seed(42)
data = np.random.normal(loc=2.5, scale=1.2, size=(100, 3))
df = pd.DataFrame(data, columns=['val_1', 'val_2', 'val_3'])
df.insert(0, 'id', range(1, 101))
df.to_csv('/home/user/observations.csv', index=False)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user
