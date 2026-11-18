#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip socat curl
    pip3 install pytest numpy scipy

    mkdir -p /app
    mkdir -p /home/user

    # Generate a dummy 16-bit PCM WAV file
    python3 -c "
import numpy as np
import scipy.io.wavfile as wavfile

rate = 8000
t = np.linspace(0, 1, rate)
# Generate a simple 440 Hz sine wave with a peak amplitude of 10000
data = (np.sin(2 * np.pi * 440 * t) * 10000).astype(np.int16)
wavfile.write('/app/ivr_greeting.wav', rate, data)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
