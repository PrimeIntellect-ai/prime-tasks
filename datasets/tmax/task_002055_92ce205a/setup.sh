#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_signal.py
import numpy as np

# Set random seed for reproducible input generation
np.random.seed(42)

# Generate 100 signals of length 1024
n_signals = 100
length = 1024
x = np.arange(length)

signals = np.zeros((n_signals, length))
expected_peaks = []

for i in range(n_signals):
    # Base frequency between 10 and 200
    freq = np.random.randint(10, 200)
    # Generate signal with noise
    signals[i] = np.sin(2 * np.pi * freq * x / length) + np.random.normal(0, 0.5, length)
    expected_peaks.append(freq)

np.save('/home/user/signal.npy', signals)
EOF

    python3 /tmp/setup_signal.py
    rm /tmp/setup_signal.py

    chmod -R 777 /home/user
