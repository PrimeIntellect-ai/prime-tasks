#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ ffmpeg
pip3 install pytest numpy scipy

mkdir -p /app/data
cat << 'EOF' > /tmp/setup_audio.py
import numpy as np
import scipy.io.wavfile as wavfile
import os

os.makedirs('/app/data', exist_ok=True)
sample_rate = 16000
duration = 10.0
t = np.linspace(0, duration, int(sample_rate * duration), endpoint=False)

# Background noise
signal = np.random.normal(0, 0.1, len(t))

# Beeps
events = [(1.5, 2.0), (4.2, 4.6), (7.8, 8.1)]
for start, end in events:
    idx_start, idx_end = int(start * sample_rate), int(end * sample_rate)
    signal[idx_start:idx_end] += 0.8 * np.sin(2 * np.pi * 4000 * t[idx_start:idx_end])

# Normalize and convert to 16-bit
signal = np.clip(signal, -1.0, 1.0)
signal_16 = np.int16(signal * 32767)
wavfile.write('/app/data/raw_audio.wav', sample_rate, signal_16)
EOF

python3 /tmp/setup_audio.py
rm /tmp/setup_audio.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
