#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scipy numpy

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    python3 -c "
import numpy as np
from scipy.io import wavfile
import os

sr = 44100
duration = 1.0
t = np.linspace(0, duration, int(sr * duration), False)

# Clean files
for i in range(3):
    noise = np.random.uniform(-1000, 1000, size=len(t)).astype(np.int16)
    wavfile.write(f'/app/corpus/clean/clean{i}.wav', sr, noise)

# Evil files
for i in range(3):
    noise = np.random.uniform(-1000, 1000, size=len(t)).astype(np.int16)
    # Insert 60ms of zeros
    start = sr // 2
    noise[start:start + int(0.06 * sr)] = 0
    wavfile.write(f'/app/corpus/evil/evil{i}.wav', sr, noise)

# Incident alert
noise = np.random.uniform(-1000, 1000, size=len(t)).astype(np.int16)
start = sr // 2
noise[start:start + int(0.1 * sr)] = 0
wavfile.write('/app/incident_alert.wav', sr, noise)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
