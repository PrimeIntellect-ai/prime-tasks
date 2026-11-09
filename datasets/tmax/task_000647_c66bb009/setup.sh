#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest numpy scipy SpeechRecognition

    # Create directories
    mkdir -p /app/audio
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate audio voicemail
    espeak -w /app/audio/voicemail.wav "Hey, it's me. After running the Monte Carlo simulations, I found the optimal cutoff. The threshold condition number is exactly eight thousand five hundred. Do not use anything higher than that. See you next week."

    # Generate corpus data
    python3 -c "
import numpy as np
import os

for i in range(20):
    # Clean matrix (well-conditioned)
    A = np.random.randn(100, 100)
    np.save(f'/app/corpus/clean/matrix_{i:03d}.npy', A)

    # Evil matrix (ill-conditioned, cond > 8500)
    B = np.random.randn(100, 100)
    B[1] = B[0] + np.random.randn(100) * 1e-5
    np.save(f'/app/corpus/evil/matrix_{i:03d}.npy', B)
"

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
