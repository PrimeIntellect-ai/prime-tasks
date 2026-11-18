#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy scikit-learn pandas

    mkdir -p /app
    cat << 'EOF' > /app/generate_audio.py
import os
import numpy as np
from scipy.io import wavfile

os.makedirs('/app', exist_ok=True)
np.random.seed(0)
sr = 16000
duration = 60
t = np.linspace(0, 1, sr, endpoint=False)
audio = np.random.randn(duration * sr) * 0.05 # background noise

# Inject distinct 440Hz sine waves into specific chunks
# Chunk 0 is the reference.
target_chunks = [0, 10, 20, 30, 40, 50]
for i in target_chunks:
    audio[i*sr:(i+1)*sr] += np.sin(2 * np.pi * 440 * t) * 0.8

# Inject a different frequency into other chunks as distractors
distractor_chunks = [5, 15, 25, 35, 45, 55]
for i in distractor_chunks:
    audio[i*sr:(i+1)*sr] += np.sin(2 * np.pi * 880 * t) * 0.8

# Scale to int16 range
audio_int16 = np.int16(audio * 32767)
wavfile.write('/app/research_audio.wav', sr, audio_int16)
EOF

    python3 /app/generate_audio.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
