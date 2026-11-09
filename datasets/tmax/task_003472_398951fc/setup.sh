#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential libhdf5-dev pkg-config rustc cargo
    pip3 install pytest numpy scipy h5py

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import scipy.io.wavfile as wav
import os

os.makedirs('/app', exist_ok=True)
os.makedirs('/truth', exist_ok=True)

fs = 16000
duration = 5.0
t = np.arange(int(fs * duration)) / fs

clean = np.zeros_like(t)
np.random.seed(42)
for _ in range(10):
    burst_t = np.random.uniform(0.5, 4.5)
    burst_len = int(fs * 0.05)
    start_idx = int(burst_t * fs)
    burst_noise = np.random.randn(burst_len)
    freq = 3250
    envelope = np.hanning(burst_len)
    clean[start_idx:start_idx+burst_len] += np.sin(2 * np.pi * freq * (np.arange(burst_len)/fs)) * envelope

clean = clean / np.max(np.abs(clean)) * 0.5
wav.write('/truth/clean_reference.wav', fs, (clean * 32767).astype(np.int16))

noise = np.random.randn(len(t)) * 0.2
noisy = clean + noise
noisy = np.clip(noisy, -1.0, 1.0)
wav.write('/app/stress_test.wav', fs, (noisy * 32767).astype(np.int16))
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
