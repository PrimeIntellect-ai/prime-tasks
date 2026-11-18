#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest numpy scipy

    mkdir -p /app

    cat << 'EOF' > /tmp/generate_wav.py
import numpy as np
from scipy.io import wavfile

sample_rate = 44100
duration = 0.1
samples_per_segment = int(sample_rate * duration)
t = np.linspace(0, duration, samples_per_segment, endpoint=False)

freqs = [1000, 2000, 1500, 2500, 1000]
signal = np.concatenate([np.sin(2 * np.pi * f * t) for f in freqs])

audio_data = np.int16(signal * 32767)
wavfile.write('/app/signal_data.wav', sample_rate, audio_data)
EOF

    python3 /tmp/generate_wav.py
    rm /tmp/generate_wav.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
