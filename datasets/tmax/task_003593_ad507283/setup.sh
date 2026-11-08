#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    # Generate the audio fixture
    python3 -c "
import numpy as np
from scipy.io import wavfile
import os

os.makedirs('/app', exist_ok=True)
fs = 16000
t = np.linspace(0, 0.25, int(fs * 0.25), endpoint=False)
f0 = 500
f1 = 2000
t1 = 0.25
phase = 2 * np.pi * (f0 * t + (f1 - f0) / (2 * t1) * t**2)
signal = np.sin(phase)

envelope = np.ones_like(t)
envelope[:100] = np.linspace(0, 1, 100)
envelope[-100:] = np.linspace(1, 0, 100)
signal = signal * envelope

wavfile.write('/app/pulse.wav', fs, (signal * 32767).astype(np.int16))
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
