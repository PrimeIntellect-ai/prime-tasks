#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libsndfile1
    pip3 install pytest numpy scipy h5py soundfile

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /tmp/setup_data.py
import numpy as np
import soundfile as sf
import h5py
import os

# Generate audio
sr = 44100
t = np.linspace(0, 1, sr, endpoint=False)
audio = np.sin(2 * np.pi * 440 * t) + np.sin(2 * np.pi * 1000 * t)
sf.write('/app/reference_profile.wav', audio, sr)

# Get top peaks for clean matrices
fft_mag = np.abs(np.fft.rfft(audio))
fft_mag_norm = fft_mag / np.sum(fft_mag)
top_peaks = np.sort(fft_mag_norm)[-100:][::-1]

N, M = 100, 100

# Generate clean matrices
for i in range(5):
    U, _ = np.linalg.qr(np.random.randn(N, N))
    V, _ = np.linalg.qr(np.random.randn(M, M))
    S = np.zeros(100)
    S[:2] = top_peaks[:2]
    matrix = U @ np.diag(S) @ V[:100]
    with h5py.File(f'/app/corpus/clean/clean_{i}.h5', 'w') as f:
        f.create_dataset('features', data=matrix)

# Generate evil matrices
for i in range(5):
    U, _ = np.linalg.qr(np.random.randn(N, N))
    V, _ = np.linalg.qr(np.random.randn(M, M))
    S = np.zeros(100)
    S[:10] = np.linspace(0.1, 0.01, 10)
    S /= np.sum(S)
    matrix = U @ np.diag(S) @ V[:100]
    with h5py.File(f'/app/corpus/evil/evil_{i}.h5', 'w') as f:
        f.create_dataset('features', data=matrix)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
