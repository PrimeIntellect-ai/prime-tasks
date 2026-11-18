#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy matplotlib

    # Create directories
    mkdir -p /app/corpus/clean /app/corpus/evil
    mkdir -p /app/verifier/clean /app/verifier/evil

    # Generate audio files
    cat << 'EOF' > /tmp/generate_audio.py
import os
import numpy as np
from scipy.io import wavfile

np.random.seed(42)

def generate_audio(filename, duration=3.0, sr=44100, is_evil=False, evil_freq=4410.0):
    t = np.linspace(0, duration, int(sr * duration), endpoint=False)
    # White noise
    signal = np.random.normal(0, 0.5, size=t.shape)
    if is_evil:
        # Add sine wave
        amplitude = np.random.uniform(0.5, 1.5)
        signal += amplitude * np.sin(2 * np.pi * evil_freq * t)

    # Normalize to 16-bit PCM
    signal = np.clip(signal / np.max(np.abs(signal)), -1.0, 1.0)
    signal_16 = np.int16(signal * 32767)
    wavfile.write(filename, sr, signal_16)

# Reference signal
generate_audio("/app/reference_signal.wav", is_evil=True)

# Corpus
for i in range(50):
    generate_audio(f"/app/corpus/clean/clean_{i:03d}.wav", is_evil=False)
    generate_audio(f"/app/corpus/evil/evil_{i:03d}.wav", is_evil=True)

# Verifier
for i in range(100):
    generate_audio(f"/app/verifier/clean/clean_{i:03d}.wav", is_evil=False)
    generate_audio(f"/app/verifier/evil/evil_{i:03d}.wav", is_evil=True)
EOF

    python3 /tmp/generate_audio.py
    rm /tmp/generate_audio.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
