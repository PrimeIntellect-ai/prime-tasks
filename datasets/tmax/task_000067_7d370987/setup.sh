#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest numpy scipy

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate the brief
    espeak -w /app/brief.wav "Set the PCA components to three. Flag any file where the first principal component explains less than thirty five percent of the total variance."

    # Generate corpus
    cat << 'EOF' > /tmp/generate_corpus.py
import os
import numpy as np
from scipy.io import wavfile

sr = 22050
duration = 2.0
t = np.linspace(0, duration, int(sr * duration), endpoint=False)

# Clean: Sine waves (highly correlated features, high 1st PCA variance)
for i in range(50):
    freq = 440 + np.random.uniform(-100, 100)
    audio = np.sin(2 * np.pi * freq * t) + 0.5 * np.sin(2 * np.pi * freq * 2 * t)
    audio = (audio * 32767 / np.max(np.abs(audio))).astype(np.int16)
    wavfile.write(f'/app/corpus/clean/clean_{i}.wav', sr, audio)

# Evil: White noise (uncorrelated features, low 1st PCA variance)
for i in range(50):
    audio = np.random.normal(0, 1.0, len(t))
    audio = (audio * 32767 / np.max(np.abs(audio))).astype(np.int16)
    wavfile.write(f'/app/corpus/evil/evil_{i}.wav', sr, audio)
EOF

    python3 /tmp/generate_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
