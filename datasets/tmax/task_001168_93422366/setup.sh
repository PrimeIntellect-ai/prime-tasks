#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy flask fastapi uvicorn requests

    mkdir -p /app
    cat << 'EOF' > /tmp/generate_audio.py
import numpy as np
import scipy.io.wavfile as wavfile
import os

os.makedirs('/app', exist_ok=True)
np.random.seed(42)

sample_rate = 16000
duration = 4.0
t = np.linspace(0, duration, int(sample_rate * duration), endpoint=False)

# Background noise
signal = np.random.normal(0, 0.1, len(t))
# Machine hum (50 Hz + harmonics)
signal += 0.5 * np.sin(2 * np.pi * 50 * t)
signal += 0.2 * np.sin(2 * np.pi * 100 * t)

# Anomaly in the second half (added high freq grind)
second_half_idx = len(t) // 2
signal[second_half_idx:] += 0.4 * np.sin(2 * np.pi * 3000 * t[second_half_idx:])
signal[second_half_idx:] += np.random.normal(0, 0.2, len(t) - second_half_idx)

# Normalize to 16-bit range
signal = np.int16(signal / np.max(np.abs(signal)) * 32767)
wavfile.write('/app/system_noise.wav', sample_rate, signal)
EOF

    python3 /tmp/generate_audio.py
    rm /tmp/generate_audio.py
    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
