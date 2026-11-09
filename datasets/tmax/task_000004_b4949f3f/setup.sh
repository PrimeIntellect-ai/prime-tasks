#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /app

    cat << 'EOF' > /tmp/generate_audio.py
import numpy as np
from scipy.io import wavfile

sr = 16000
duration = 2.0
t = np.arange(int(sr * duration)) / sr

f = [440.0, 880.0, 1320.0]
A = [0.8, 0.4, 0.2]
lam = [1.5, 3.0, 5.0]
phi = [0.0, 1.57, 3.14]

S = np.zeros_like(t)
for i in range(3):
    S += A[i] * np.exp(-lam[i] * t) * np.sin(2 * np.pi * f[i] * t + phi[i])

np.random.seed(42)
noise = np.random.normal(0, 0.05, len(t))
S += noise

# Normalize to 16-bit PCM range
S = S / np.max(np.abs(S))
S_int = np.int16(S * 32767)

wavfile.write('/app/chime_recording.wav', sr, S_int)
EOF

    python3 /tmp/generate_audio.py
    rm /tmp/generate_audio.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
