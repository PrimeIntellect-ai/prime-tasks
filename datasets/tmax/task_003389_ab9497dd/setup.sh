#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc curl
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/gen_wav.py
import wave, struct, math
out = wave.open('/app/test_signal.wav', 'w')
out.setnchannels(1)
out.setsampwidth(2)
out.setframerate(44100)
frames = []
for i in range(44100):
    val = int(30000 * math.sin(2 * math.pi * 440 * (i / 44100.0)))
    frames.append(struct.pack('<h', val))
out.writeframes(b''.join(frames))
out.close()
EOF

    python3 /tmp/gen_wav.py
    rm /tmp/gen_wav.py

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/workspace
    chmod -R 777 /home/user
