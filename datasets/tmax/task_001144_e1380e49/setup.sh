#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    # Create the /app directory
    mkdir -p /app

    # Generate the audio file
    cat << 'EOF' > /tmp/generate_audio.py
import numpy as np
import scipy.io.wavfile as wav
import os

os.makedirs('/app', exist_ok=True)

fs = 8000
duration = 3.0
t = np.arange(int(fs * duration)) / fs

# True parameters for the decaying sine waves (impulse response)
f_true = [440.0, 880.0, 1500.0]
gamma_true = [5.0, 12.0, 20.0]
A_true = [1.0, 0.6, 0.4]

y = np.zeros_like(t)
for f, g, A in zip(f_true, gamma_true, A_true):
    y += A * np.exp(-g * t) * np.sin(2 * np.pi * f * t)

# Add Gaussian noise
np.random.seed(42)
y += np.random.normal(0, 0.05, size=len(t))

# Normalize to 16-bit PCM range and save
y_norm = np.int16(y / np.max(np.abs(y)) * 32767)
wav.write('/app/acoustic_test.wav', fs, y_norm)
EOF

    python3 /tmp/generate_audio.py
    rm /tmp/generate_audio.py

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
