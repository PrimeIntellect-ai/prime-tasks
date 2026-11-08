#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np

np.random.seed(42)
N = 100
M = 51 # dx = 0.02
x = np.linspace(0, 1, M)

signals = []
for i in range(N):
    # Base smooth signal
    freq = np.random.uniform(0.5, 2.0)
    phase = np.random.uniform(0, 2 * np.pi)
    amp = np.random.uniform(0.5, 1.5)
    sig = amp * np.sin(2 * np.pi * freq * x + phase)

    # Inject numerical instability in some signals
    if np.random.rand() < 0.3:
        sig += 0.05 * np.sin(2 * np.pi * 20 * x)

    signals.append(sig)

signals = np.array(signals)
np.save('/home/user/raw_signals.npy', signals)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
