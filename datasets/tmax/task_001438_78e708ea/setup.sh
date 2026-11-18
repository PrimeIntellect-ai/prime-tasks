#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd

# Setup data
np.random.seed(42)
t = np.linspace(0, 10, 1000, endpoint=False) # fs = 100 Hz
# True parameters: f = 2.5 Hz, A = 4.2, phi = 0.5, C = 2.0
y_true = 4.2 * np.sin(2 * np.pi * 2.5 * t + 0.5) + 2.0
y_noisy = y_true + np.random.normal(0, 0.5, size=len(t))

df = pd.DataFrame({'t': t, 'y': y_noisy})
df.to_csv('/home/user/signal.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
