#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libsndfile1
    pip3 install pytest numpy scipy librosa

    # Create directories
    mkdir -p /app/train/clean /app/train/evil /app/test/clean /app/test/evil

    # Generate audio files
    cat << 'EOF' > /tmp/generate_audio.py
import os
import numpy as np
from scipy.io import wavfile

sr = 44100
t = np.linspace(0, 5, sr * 5)

# Create ambient baseline (audio fixture)
ambient = np.random.normal(0, 0.1, len(t))
wavfile.write('/app/ambient_baseline.wav', sr, np.int16(ambient * 32767))

def generate_clean(path):
    # Noise + some harmonics, well-conditioned
    sig = np.random.normal(0, 0.1, len(t)) + 0.2 * np.sin(2 * np.pi * 440 * t)
    wavfile.write(path, sr, np.int16(sig * 32767))

def generate_evil(path, type_idx):
    if type_idx == 0:
        # Pure sine (near-singular spectrogram)
        sig = 0.5 * np.sin(2 * np.pi * 1000 * t)
    elif type_idx == 1:
        # Absolute silence (singular)
        sig = np.zeros_like(t)
    else:
        # DC offset only
        sig = np.ones_like(t) * 0.5
    wavfile.write(path, sr, np.int16(sig * 32767))

# Generate Train
for i in range(10): generate_clean(f'/app/train/clean/clean_{i}.wav')
for i in range(10): generate_evil(f'/app/train/evil/evil_{i}.wav', i % 3)

# Generate Test
for i in range(20): generate_clean(f'/app/test/clean/clean_{i}.wav')
for i in range(20): generate_evil(f'/app/test/evil/evil_{i}.wav', i % 3)
EOF

    python3 /tmp/generate_audio.py
    rm /tmp/generate_audio.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
