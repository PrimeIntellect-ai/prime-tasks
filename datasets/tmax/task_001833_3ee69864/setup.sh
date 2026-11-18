#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl openssh-server openssh-client g++
    pip3 install pytest numpy scipy pandas

    mkdir -p /app
    cat << 'EOF' > /tmp/generate_wav.py
import numpy as np
import scipy.io.wavfile as wav

rate = 44100
duration = 2.0 # seconds
t = np.linspace(0, duration, int(rate * duration), endpoint=False)
data = (np.sin(2 * np.pi * 440 * t) * 10000).astype(np.int16)
wav.write('/app/sonar_data.wav', rate, data)
EOF
    python3 /tmp/generate_wav.py
    rm /tmp/generate_wav.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
