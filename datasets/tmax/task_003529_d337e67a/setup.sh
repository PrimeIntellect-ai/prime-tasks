#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_signal.py
import numpy as np

def generate_signal():
    np.random.seed(42)
    t = np.arange(0, 5, 0.01) # 500 points, 100 Hz

    # Base signal: 2 Hz and 6 Hz
    y = 5.0 * np.sin(2 * np.pi * 2 * t) + 3.0 * np.cos(2 * np.pi * 6 * t)

    # High frequency noise: 25 Hz and 40 Hz
    noise = 15.0 * np.sin(2 * np.pi * 25 * t) + 10.0 * np.random.randn(len(t))

    signal = y + noise
    np.savetxt('/home/user/signal.csv', signal, fmt='%.6f')

generate_signal()
EOF

    python3 /tmp/generate_signal.py
    rm /tmp/generate_signal.py

    chmod -R 777 /home/user
