#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /app /truth

    cat << 'EOF' > /tmp/setup.py
import numpy as np
from scipy.io import wavfile
import os

os.makedirs('/app', exist_ok=True)
os.makedirs('/truth', exist_ok=True)

sr = 16000
duration = 5.0
t = np.linspace(0, duration, int(sr * duration), endpoint=False)

# Create a clean signal: 1s 1kHz tone + 4s of mixed frequencies (simulating speech/commands)
tone = 0.8 * np.sin(2 * np.pi * 1000 * t[:sr])
speech = 0.5 * np.sin(2 * np.pi * 300 * t[sr:]) + 0.3 * np.sin(2 * np.pi * 1500 * t[sr:]) + 0.1 * np.random.randn(int(sr * (duration - 1)))
clean_signal = np.concatenate([tone, speech])

# Apply non-linear distortion: y = x - 0.15 * x^3
distorted_signal = clean_signal - 0.15 * (clean_signal**3)

# Save expected clean
wavfile.write('/truth/expected_clean.wav', sr, (clean_signal * 32767).astype(np.int16))

# Save distorted to /app
wavfile.write('/app/distorted_commands.wav', sr, (distorted_signal * 32767).astype(np.int16))
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
