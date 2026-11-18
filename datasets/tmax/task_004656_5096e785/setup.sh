#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cargo rustc
pip3 install pytest

mkdir -p /app
mkdir -p /home/user

cat << 'EOF' > /tmp/gen_wav.py
import wave
import math
import struct

sample_rate = 44100
duration = 10
frequency = 440.0
num_samples = sample_rate * duration

with wave.open('/app/token.wav', 'wb') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(sample_rate)
    for i in range(num_samples):
        value = int(32767.0 * math.sin(2.0 * math.pi * frequency * i / sample_rate))
        data = struct.pack('<h', value)
        w.writeframesraw(data)
EOF

python3 /tmp/gen_wav.py
rm /tmp/gen_wav.py

cat << 'EOF' > /home/user/audit.log
[INFO] System startup
[CRITICAL] Leakage detected - start: 1.500s, duration: 0.500s
[WARN] Network interface eth0 down
[CRITICAL] Leakage detected - start: 4.125s, duration: 0.875s
[CRITICAL] Leakage detected - start: 8.000s, duration: 1.000s
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /app
chmod -R 777 /home/user
