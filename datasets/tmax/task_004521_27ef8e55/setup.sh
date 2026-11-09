#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-numpy python3-scipy espeak sox ffmpeg
    pip3 install pytest

    mkdir -p /app/data/clean
    mkdir -p /app/data/evil

    # Generate secret instructions audio
    espeak -w /app/secret_instructions.wav "The numerical integration is considered divergent if the absolute amplitude exceeds zero point nine eight for more than five consecutive samples."

    # Generate clean and evil audio files
    python3 -c "
import numpy as np
import scipy.io.wavfile as wavfile
import os

sample_rate = 16000
duration = 1.0
t = np.linspace(0, duration, int(sample_rate * duration), endpoint=False)

for i in range(15):
    # Clean audio
    clean_data = 0.5 * np.sin(2 * np.pi * 440 * t)
    wavfile.write(f'/app/data/clean/clean_{i}.wav', sample_rate, clean_data.astype(np.float32))

    # Evil audio: starts normal, then has 10 consecutive samples > 0.98
    evil_data = 0.5 * np.sin(2 * np.pi * 440 * t)
    evil_data[10000:10010] = 0.99
    wavfile.write(f'/app/data/evil/evil_{i}.wav', sample_rate, evil_data.astype(np.float32))
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
