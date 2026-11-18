#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    apt-get install -y git build-essential python3-numpy python3-scipy libsndfile1-dev pkg-config

    mkdir -p /app/corpus/clean /app/corpus/evil /app/src

    cat << 'EOF' > /tmp/generate_wavs.py
import numpy as np
import scipy.io.wavfile as wavfile
import os

sample_rate = 44100
duration = 1.0
t = np.linspace(0, duration, int(sample_rate * duration), endpoint=False)

# Generate CLEAN (Valid bio-signals: Sine wave + slight noise)
os.makedirs('/app/corpus/clean', exist_ok=True)
for i in range(20):
    freq = np.random.uniform(300, 800)
    signal = np.sin(2 * np.pi * freq * t)
    noise = np.random.normal(0, 0.1, signal.shape)
    audio = signal + noise
    audio = np.int16(audio / np.max(np.abs(audio)) * 32767)
    wavfile.write(f'/app/corpus/clean/signal_{i:02d}.wav', sample_rate, audio)

# Generate EVIL (Noise only misreads: Pure white noise)
os.makedirs('/app/corpus/evil', exist_ok=True)
for i in range(20):
    noise = np.random.normal(0, 1.0, int(sample_rate * duration))
    audio = np.int16(noise / np.max(np.abs(noise)) * 32767)
    wavfile.write(f'/app/corpus/evil/noise_{i:02d}.wav', sample_rate, audio)

# Generate Fixture
signal1 = np.sin(2 * np.pi * 440 * t)
noise_gap = np.random.normal(0, 1.0, int(sample_rate * 0.5))
signal2 = np.sin(2 * np.pi * 523 * t)
signal3 = np.sin(2 * np.pi * 659 * t)

fixture_audio = np.concatenate([signal1, noise_gap, signal2, noise_gap, signal3])
fixture_audio = np.int16(fixture_audio / np.max(np.abs(fixture_audio)) * 32767)
wavfile.write('/app/sample.wav', sample_rate, fixture_audio)
EOF

    python3 /tmp/generate_wavs.py
    rm /tmp/generate_wavs.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /app
    chmod -R 777 /home/user
