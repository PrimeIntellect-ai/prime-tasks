#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy h5py

    mkdir -p /app

    # Generate the audio file
    cat << 'EOF' > /tmp/gen_audio.py
import numpy as np
from scipy.io import wavfile

fs = 44100
t = np.linspace(0, 5, 5 * fs, endpoint=False)
np.random.seed(42)
noise = np.random.normal(0, 1, len(t))

# Apply a simple low-pass filter to create a decaying frequency spectrum
filtered_noise = np.zeros_like(noise)
filtered_noise[0] = noise[0]
for i in range(1, len(noise)):
    filtered_noise[i] = 0.9 * filtered_noise[i-1] + 0.1 * noise[i]

# Normalize and save
filtered_noise = filtered_noise / np.max(np.abs(filtered_noise))
wavfile.write('/app/turbine_audio.wav', fs, filtered_noise.astype(np.float32))
EOF

    python3 /tmp/gen_audio.py
    rm /tmp/gen_audio.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
