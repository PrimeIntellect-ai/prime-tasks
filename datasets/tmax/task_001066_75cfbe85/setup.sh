#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip libsndfile1
pip3 install --no-cache-dir pytest numpy scipy librosa soundfile

mkdir -p /app
cat << 'EOF' > /app/generate_audio.py
import numpy as np
from scipy.io import wavfile

np.random.seed(0)
sr = 16000
duration = 15 # seconds
t = np.linspace(0, duration, sr * duration, endpoint=False)
# Generate a mix of frequencies and noise
y = 0.5 * np.sin(2 * np.pi * 440 * t) + 0.25 * np.sin(2 * np.pi * 880 * t) + np.random.normal(0, 0.1, len(t))
# Save as 16-bit PCM WAV
wavfile.write('/app/input_audio.wav', sr, (y * 32767).astype(np.int16))
EOF

python3 /app/generate_audio.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
