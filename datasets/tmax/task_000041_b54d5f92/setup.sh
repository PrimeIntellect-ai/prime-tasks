#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang curl
    pip3 install pytest

    mkdir -p /app
    python3 -c "
import wave, struct, math
sample_rate = 8000
num_samples = 8000
peak_amp = 15000

with wave.open('/app/source.wav', 'w') as w:
    w.setnchannels(1)
    w.setsampwidth(2) # 16-bit
    w.setframerate(sample_rate)

    for i in range(num_samples):
        # Add a spike to ensure exactly 15000 is hit, otherwise just a sine wave
        if i == 4000:
            val = 15000
        else:
            val = int(10000 * math.sin(2 * math.pi * 440.0 * (i / sample_rate)))
        data = struct.pack('<h', val)
        w.writeframesraw(data)
"

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/sim_server
    chmod -R 777 /home/user
