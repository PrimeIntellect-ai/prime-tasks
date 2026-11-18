#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-numpy python3-scipy curl build-essential rustc cargo
    pip3 install pytest

    cat << 'EOF' > /tmp/gen_wav.py
import numpy as np
import scipy.io.wavfile as wavfile
import os

os.makedirs('/app', exist_ok=True)
sample_rate = 44100
duration = 2.0
t = np.linspace(0, duration, int(sample_rate * duration), endpoint=False)
# Generate signal with 1500Hz and 4000Hz components
signal = 0.4 * np.sin(2 * np.pi * 1500 * t) + 0.3 * np.sin(2 * np.pi * 4000 * t)
# Add a little noise
np.random.seed(42)
signal += np.random.normal(0, 0.05, signal.shape)
# Convert to 16-bit PCM
signal = np.int16(signal * 32767)
wavfile.write('/app/stress_test.wav', sample_rate, signal)
EOF

    python3 /tmp/gen_wav.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
