#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    # Create /app directory
    mkdir -p /app

    # Generate the fixture.wav file using built-in Python modules
    python3 -c "
import wave
import struct
import math

sample_rate = 16000
duration = 3
num_samples = sample_rate * duration

with wave.open('/app/fixture.wav', 'w') as f:
    f.setnchannels(1)
    f.setsampwidth(2) # 16-bit
    f.setframerate(sample_rate)
    for i in range(num_samples):
        value = int(32767.0 * math.sin(2.0 * math.pi * 440.0 * i / sample_rate))
        data = struct.pack('<h', value)
        f.writeframesraw(data)
"

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
