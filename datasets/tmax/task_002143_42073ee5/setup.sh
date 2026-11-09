#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy librosa soundfile

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /tmp/generate_audio.py
import numpy as np
from scipy.io import wavfile
import os

sr = 16000
t = np.linspace(0, 1, sr)

# Clean signal (e.g., random sparse noise to simulate speech without hum)
clean_sig = np.random.randn(sr) * 0.1
wavfile.write('/app/corpus/clean/clean_01.wav', sr, clean_sig.astype(np.float32))

# Evil signal (clean + low-rank interference like a 60Hz and 120Hz hum)
hum = 0.5 * np.sin(2 * np.pi * 60 * t) + 0.5 * np.sin(2 * np.pi * 120 * t)
evil_sig = clean_sig + hum
wavfile.write('/app/corpus/evil/evil_01.wav', sr, evil_sig.astype(np.float32))

# Sample interference file
wavfile.write('/app/sample_interference.wav', sr, evil_sig.astype(np.float32))
EOF

    python3 /tmp/generate_audio.py
    rm /tmp/generate_audio.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
