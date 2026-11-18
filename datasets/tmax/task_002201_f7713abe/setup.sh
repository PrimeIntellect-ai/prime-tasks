#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest numpy scipy librosa flask fastapi uvicorn scikit-learn pydantic httpx

cat << 'EOF' > /tmp/gen_audio.py
import numpy as np
import scipy.io.wavfile as wavfile
import os

os.makedirs('/app', exist_ok=True)
sr = 22050
t1 = np.linspace(0, 5, sr * 5, endpoint=False)
audio1 = 0.5 * np.sin(2 * np.pi * 440 * t1) # 440 Hz for 5 seconds

t2 = np.linspace(0, 5, sr * 5, endpoint=False)
audio2 = 0.5 * np.sin(2 * np.pi * 880 * t2) # 880 Hz for 5 seconds

audio = np.concatenate([audio1, audio2])
# Convert to int16 so standard wave module can read it without format errors
audio_int = (audio * 32767).astype(np.int16)
wavfile.write('/app/data.wav', sr, audio_int)
EOF

python3 /tmp/gen_audio.py
rm /tmp/gen_audio.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
