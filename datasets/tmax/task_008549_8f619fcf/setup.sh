#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup.py
import numpy as np

# Generate signal
N = 100000
t = np.arange(N)
# Signal with 3 distinct cosine waves. 
# Magnitudes in normalized FFT (divided by N) for cos will be Amplitude / 2
# Top 3 expected magnitudes: 5.7/2 = 2.85, 3.2/2 = 1.6, 1.1/2 = 0.55
signal = 5.7 * np.cos(2*np.pi * 1200 * t / N) + 3.2 * np.cos(2*np.pi * 500 * t / N) + 1.1 * np.cos(2*np.pi * 3400 * t / N)
np.save('/home/user/signal.npy', signal)

# Generate models
np.random.seed(42)
models = np.random.uniform(0, 5, (50000, 3))
# Inject the exact expected answer at index 1337
models[1337] = [2.85, 1.6, 0.55]
np.save('/home/user/models.npy', models)
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
