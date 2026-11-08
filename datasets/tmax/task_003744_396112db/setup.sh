#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest numpy pandas

    mkdir -p /home/user
    cat << 'EOF' > /home/user/setup_data.py
import numpy as np
import pandas as pd

np.random.seed(42)
x = np.random.normal(0, 1, 100)
y = 2 * x
df = pd.DataFrame({'x': x, 'y': y})
df.to_csv('/home/user/sim_data.csv', index=False)
EOF
    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
