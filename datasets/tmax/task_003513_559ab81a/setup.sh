#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /app

    cat << 'EOF' > /tmp/gen_audio.py
import numpy as np
from scipy.io import wavfile

sample_rate = 8000
duration = 2.0
t = np.linspace(0, duration, int(sample_rate * duration), endpoint=False)

# Frequencies: 440 Hz, 554 Hz, 659 Hz (A Major)
signal = np.sin(2 * np.pi * 440 * t) + \
         0.8 * np.sin(2 * np.pi * 554 * t) + \
         0.6 * np.sin(2 * np.pi * 659 * t)

# Add Gaussian noise
np.random.seed(42)
signal += np.random.normal(0, 0.5, signal.shape)

# Normalize and save
signal = np.int16(signal / np.max(np.abs(signal)) * 32767)
wavfile.write("/app/signal.wav", sample_rate, signal)
EOF

    python3 /tmp/gen_audio.py
    rm /tmp/gen_audio.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
