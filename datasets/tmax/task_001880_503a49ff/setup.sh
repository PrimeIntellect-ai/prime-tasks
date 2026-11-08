#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy soundfile

    mkdir -p /app

    # Generate the suspicious.wav file
    python3 -c "
import numpy as np
from scipy.io import wavfile

rate = 44100
t = np.linspace(0, 1, rate, endpoint=False)
# 400 Hz signal
signal = np.sin(2 * np.pi * 400 * t)
# 8000 Hz noise
noise = 0.5 * np.sin(2 * np.pi * 8000 * t)
data = signal + noise
data = np.int16(data / np.max(np.abs(data)) * 32767)
wavfile.write('/app/suspicious.wav', rate, data)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
