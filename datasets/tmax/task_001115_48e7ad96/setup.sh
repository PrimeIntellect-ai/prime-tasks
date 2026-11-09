#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make cmake libhdf5-dev libsndfile1-dev
    pip3 install pytest numpy scipy

    mkdir -p /app

    cat << 'EOF' > /tmp/setup.py
import numpy as np
from scipy.io import wavfile
import os

os.makedirs('/app', exist_ok=True)

fs = 8000
t = np.arange(fs) / fs

A1, alpha1, f1 = 0.8, 2.0, 440.0
A2, alpha2, f2 = 0.6, 1.5, 445.0

s_clean = A1 * np.exp(-alpha1 * t) * np.sin(2 * np.pi * f1 * t) + \
          A2 * np.exp(-alpha2 * t) * np.sin(2 * np.pi * f2 * t)

np.random.seed(42)
noise = np.random.normal(0, 0.1, len(t))
s_noisy = s_clean + noise

scale_factor = 32767.0 / 2.0
s_wav = np.clip(s_noisy * scale_factor, -32768, 32767).astype(np.int16)

wavfile.write('/app/signal.wav', fs, s_wav)
np.save('/app/s_clean.npy', s_clean)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
