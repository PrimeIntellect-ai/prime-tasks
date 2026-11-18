#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        espeak-ng \
        libopenmpi-dev \
        curl

    pip3 install pytest numpy scipy flask fastapi uvicorn SpeechRecognition pocketsphinx mpi4py

    mkdir -p /app
    espeak-ng -w /tmp/voice.wav "The thermal limit is eighty two."

    python3 -c "
import numpy as np
import scipy.io.wavfile as wavfile

sr, voice = wavfile.read('/tmp/voice.wav')
if voice.ndim > 1:
    voice = voice.mean(axis=1)
t = np.arange(len(voice)) / sr
voice = voice / (np.max(np.abs(voice)) + 1e-9)
hum = 0.5 * np.sin(2 * np.pi * 140 * t)
mixed = voice + hum
mixed = mixed / (np.max(np.abs(mixed)) + 1e-9) * 32767
wavfile.write('/app/hpc_ambient.wav', sr, mixed.astype(np.int16))
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
