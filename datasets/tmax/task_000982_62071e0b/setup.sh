#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/gen_audio.py
import wave
import math
import struct
import hashlib

payload = b"EXFIL_DATA_CONFIDENTIAL_9921"
h = hashlib.sha256(payload).hexdigest()
hex_payload = payload.hex() + h

mapping = {'e': '*', 'f': '#'}
dtmf_chars = ''.join([mapping.get(c, c).upper() for c in hex_payload])

DTMF_FREQS = {
    '1': (697, 1209), '2': (697, 1336), '3': (697, 1477), 'A': (697, 1633),
    '4': (770, 1209), '5': (770, 1336), '6': (770, 1477), 'B': (770, 1633),
    '7': (852, 1209), '8': (852, 1336), '9': (852, 1477), 'C': (852, 1633),
    '*': (941, 1209), '0': (941, 1336), '#': (941, 1477), 'D': (941, 1633),
}

sample_rate = 8000
duration = 0.1
pause = 0.05

with wave.open('/app/evidence.wav', 'w') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(sample_rate)

    for char in dtmf_chars:
        f1, f2 = DTMF_FREQS[char]
        for i in range(int(sample_rate * duration)):
            t = float(i) / sample_rate
            val = int(32767 * 0.5 * (math.sin(2 * math.pi * f1 * t) + math.sin(2 * math.pi * f2 * t)))
            f.writeframesraw(struct.pack('<h', val))
        for i in range(int(sample_rate * pause)):
            f.writeframesraw(struct.pack('<h', 0))
EOF
    python3 /tmp/gen_audio.py
    rm /tmp/gen_audio.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
