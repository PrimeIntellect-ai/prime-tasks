#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest numpy scipy

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /tmp/generate_audio.py
import numpy as np
from scipy.io import wavfile
import os

def generate_wav(path, is_evil):
    sample_rate = 44100
    duration = 2.0
    t = np.linspace(0, duration, int(sample_rate * duration), endpoint=False)

    # Generate some random noise
    signal = np.random.randn(len(t)) * 0.5

    if is_evil:
        # Inject 14,500 Hz tone
        signal += 0.05 * np.sin(2 * np.pi * 14500 * t)

    # Normalize to 16-bit PCM
    signal = np.int16(signal / np.max(np.abs(signal)) * 32767)

    wavfile.write(path, sample_rate, signal)

generate_wav('/app/reference_clean.wav', False)
generate_wav('/app/reference_evil.wav', True)

for i in range(5):
    generate_wav(f'/app/corpus/clean/clean_{i}.wav', False)
    generate_wav(f'/app/corpus/evil/evil_{i}.wav', True)
EOF

    python3 /tmp/generate_audio.py
    rm /tmp/generate_audio.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
