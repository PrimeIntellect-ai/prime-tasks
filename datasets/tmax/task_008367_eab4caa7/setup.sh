#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy

    useradd -m -s /bin/bash user || true

    # Generate the initial dataset
    cat << 'EOF' > /tmp/setup_data.py
import numpy as np
import pandas as pd

def setup_data():
    np.random.seed(123)
    N = 1000
    fs = 100.0
    t = np.linspace(0, N/fs, N, endpoint=False)

    A_true = 1.2
    C_true = A_true * np.exp(A_true) # ~3.98414
    f_true = 3.0

    y = C_true * np.sin(2 * np.pi * f_true * t) + np.random.normal(0, 0.5, N)

    df = pd.DataFrame({'t': t, 'y': y})
    df.to_csv('/home/user/noisy_signal.csv', index=False)

if __name__ == "__main__":
    setup_data()
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
