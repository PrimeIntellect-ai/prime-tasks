#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gzip
    pip3 install pytest numpy

    mkdir -p /app
    python3 -c "
import wave
import struct
import random
with wave.open('/app/artifact_raw.wav', 'w') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(44100)
    data = [random.randint(-32000, 32000) for _ in range(44100)]
    f.writeframes(struct.pack('<' + 'h'*len(data), *data))
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
