#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc python3-scipy python3-numpy
    pip3 install pytest

    mkdir -p /app

    # Generate the audio file /app/signal.wav
    python3 -c "
import numpy as np
from scipy.io import wavfile

sample_rate = 44100
duration = 2.0
t = np.linspace(0, duration, int(sample_rate * duration), endpoint=False)
np.random.seed(42)
# Generate some noise
noise = np.random.normal(0, 0.12, len(t))
# Convert to 16-bit PCM
noise_int16 = np.int16(noise * 32767)
wavfile.write('/app/signal.wav', sample_rate, noise_int16)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
