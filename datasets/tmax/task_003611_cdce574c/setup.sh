#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest numpy scipy

mkdir -p /app

# Generate the input WAV file
cat << 'EOF' > /tmp/gen_wav.py
import numpy as np
from scipy.io import wavfile

sample_rate = 44100
t = np.linspace(0, 1, sample_rate, False)
# Generate a 440 Hz sine wave
audio_data = np.sin(2 * np.pi * 440 * t) * 32767
audio_data = audio_data.astype(np.int16)
wavfile.write('/app/input.wav', sample_rate, audio_data)
EOF
python3 /tmp/gen_wav.py
rm /tmp/gen_wav.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
