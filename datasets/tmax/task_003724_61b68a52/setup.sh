#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest numpy scipy

    mkdir -p /app
    python3 -c "
import numpy as np
import scipy.io.wavfile as wavfile

rate = 16000
duration = 20
t = np.linspace(0, duration, rate * duration, endpoint=False)
# Generate some varied audio
data = np.sin(2 * np.pi * 440 * t) * np.exp(-t/5) + np.sin(2 * np.pi * 880 * t + 0.1)
# Add noise
np.random.seed(42)
data += np.random.normal(0, 0.5, size=data.shape)
data = (data / np.max(np.abs(data)) * 32767).astype(np.int16)
wavfile.write('/app/experiment_audio.wav', rate, data)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
