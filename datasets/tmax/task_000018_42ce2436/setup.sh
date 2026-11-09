#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 python3-pip \
        python3-numpy python3-scipy python3-mpi4py \
        openmpi-bin libopenmpi-dev \
        espeak \
        && rm -rf /var/lib/apt/lists/*

    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate the audio file
    espeak -w /app/lab_notes.wav "To process the new batch, please use the Nelder-Mead optimization method to fit the background. Reject any sequence where the residual spectral peak exceeds a threshold of 18.4."

    # Generate the .npy files
    python3 -c "
import numpy as np
import os

def make_signal(is_evil, idx):
    N = 1000
    t = np.linspace(0, 1, N, endpoint=False)
    freq = 50

    # FFT peak magnitude for a sine wave is (amp * N / 2)
    # We want peak > 18.4 for evil (e.g., 25.0), and < 18.4 for clean (e.g., 10.0)
    target_peak = 25.0 if is_evil else 10.0
    amp = target_peak * 2.0 / N

    sig = amp * np.sin(2 * np.pi * freq * t)

    # Add some noise to create a flat background
    noise = np.random.normal(0, 0.01, N)
    sig += noise

    filename = f\"{'evil' if is_evil else 'clean'}_{idx:03d}.npy\"
    filepath = os.path.join('/app/corpus', 'evil' if is_evil else 'clean', filename)
    np.save(filepath, sig)

for i in range(100):
    make_signal(False, i)
    make_signal(True, i)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
