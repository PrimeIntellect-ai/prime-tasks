#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ curl wget
    pip3 install pytest requests

    mkdir -p /app

    # Generate a sample 16-bit PCM Mono WAV file
    python3 -c "
import wave
import struct
import math

sample_rate = 16000
duration = 2 # seconds
num_samples = sample_rate * duration

with wave.open('/app/dataset_sample.wav', 'w') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(sample_rate)
    for i in range(num_samples):
        # 440 Hz sine wave
        value = int(32767.0 * math.sin(2.0 * math.pi * 440.0 * i / sample_rate))
        data = struct.pack('<h', value)
        f.writeframesraw(data)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
