#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy matplotlib flask fastapi uvicorn requests

    useradd -m -s /bin/bash user || true
    mkdir -p /app

    python3 -c '
import numpy as np
import scipy.io.wavfile as wav
import os

# Generate audio fixture
sample_rate = 8000
duration = 1.0
t = np.linspace(0, duration, int(sample_rate * duration), endpoint=False)
signal = np.sin(2 * np.pi * 300 * t) + 0.5 * np.sin(2 * np.pi * 600 * t) + 0.25 * np.sin(2 * np.pi * 900 * t)
signal = signal / np.max(np.abs(signal))
wav.write("/app/signal.wav", sample_rate, signal.astype(np.float32))

# Generate CSV data
np.random.seed(42)
samples = np.random.normal(50, 15, 200)
np.savetxt("/home/user/samples.csv", samples, fmt="%.4f")
'

    chmod -R 777 /home/user
    chmod -R 777 /app
