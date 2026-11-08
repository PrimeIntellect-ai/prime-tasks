#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest h5py numpy scipy flask gTTS pydub

    mkdir -p /app

    # Generate HDF5 file
    python3 -c "
import h5py
import numpy as np

# Sample rate: 1000 Hz, Duration: 2 seconds
t = np.linspace(0, 2, 2000, endpoint=False)
# Dominant frequency: 50 Hz
signal = np.sin(2 * np.pi * 50 * t) + np.random.normal(0, 0.5, 2000)

with h5py.File('/app/sequence_data.h5', 'w') as f:
    f.create_dataset('/nanopore/signal_1', data=signal)
"

    # Generate Audio file
    python3 -c "
from gtts import gTTS
import subprocess

text = 'Please analyze the nanopore data. Once you find the dominant frequency, use it as V max in the Hill equation. Solve the equation: 15 equals V max times S to the power of 2.5, divided by 100 plus S to the power of 2.5. Serve the value of S.'
tts = gTTS(text)
tts.save('/app/temp.mp3')
subprocess.run(['ffmpeg', '-i', '/app/temp.mp3', '/app/field_notes.wav'])
"
    rm -f /app/temp.mp3

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
