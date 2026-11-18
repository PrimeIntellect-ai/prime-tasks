#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc netcat
    pip3 install pytest

    # Create /app directory and generate audio.wav
    mkdir -p /app
    python3 -c "
import wave, struct, random
with wave.open('/app/audio.wav', 'w') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(44100)
    random.seed(42)
    # Generate 2000 samples
    samples = [random.randint(-32768, 32767) for _ in range(2000)]
    data = struct.pack('<' + 'h'*len(samples), *samples)
    w.writeframes(data)
"

    # Create user and home directory
    useradd -m -s /bin/bash user || true

    # Create an empty server.c
    touch /home/user/server.c

    chmod -R 777 /home/user
    chmod -R 777 /app
