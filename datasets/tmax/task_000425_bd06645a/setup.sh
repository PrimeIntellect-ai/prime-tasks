#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sudo python3-numpy python3-scipy
    pip3 install pytest

    mkdir -p /app/data

    cat << 'EOF' > /tmp/generate_audio.py
import numpy as np
from scipy.io import wavfile
import random

np.random.seed(42)
random.seed(42)

sample_rate = 16000
duration_per_bit = 0.1
num_bits = 100

t_bit = np.linspace(0, duration_per_bit, int(sample_rate * duration_per_bit), endpoint=False)

bits = [random.choice([0, 1]) for _ in range(num_bits)]

signal = []
for b in bits:
    freq = 1000 if b == 0 else 2000
    wave = np.sin(2 * np.pi * freq * t_bit)
    signal.append(wave)

signal = np.concatenate(signal)

# Add heavy white noise
noise = np.random.normal(0, 1.5, len(signal))
noisy_signal = signal + noise

# Normalize to int16
noisy_signal = np.int16(noisy_signal / np.max(np.abs(noisy_signal)) * 32767)

wavfile.write('/app/data/signal.wav', sample_rate, noisy_signal)

with open('/app/data/ground_truth.txt', 'w') as f:
    for b in bits:
        f.write(f"{b}\n")
EOF

    python3 /tmp/generate_audio.py
    rm /tmp/generate_audio.py

    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    chmod -R 777 /home/user
    chmod -R 777 /app
