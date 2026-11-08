#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest numpy pandas

    mkdir -p /app
    cat << 'EOF' > /app/generate_audio.py
import wave
import struct
import numpy as np
import math

np.random.seed(42)
sample_rate = 16000
frame_size = 1600

# Generate 50 frames (5 seconds)
# Frame 0-9: Idle
# Frame 10-29: Active
# Frame 30-49: Idle
frames = []
for i in range(50):
    if 10 <= i < 30:
        # Active: target RMS around 5000
        # For a zero-mean sequence, RMS = std_dev.
        samples = np.random.normal(0, 5000, frame_size)
    else:
        # Idle: target RMS around 500
        samples = np.random.normal(0, 500, frame_size)

    # Clip to int16 range
    samples = np.clip(samples, -32768, 32767).astype(np.int16)
    frames.append(samples)

audio_data = np.concatenate(frames)

with wave.open('/app/machine_sound.wav', 'w') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(sample_rate)
    f.writeframes(audio_data.tobytes())
EOF
    python3 /app/generate_audio.py
    rm /app/generate_audio.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
