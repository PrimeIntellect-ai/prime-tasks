#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg
pip3 install pytest numpy scipy pydub

mkdir -p /app
python3 -c "
import numpy as np
from scipy.io import wavfile
samplerate = 44100
t = np.linspace(0., 1., samplerate)
amplitude = np.iinfo(np.int16).max * 0.25
data = amplitude * np.sin(2. * np.pi * 440. * t)
wavfile.write('/app/input.wav', samplerate, data.astype(np.int16))
"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
