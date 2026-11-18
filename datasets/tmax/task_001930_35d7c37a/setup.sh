#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest numpy

    mkdir -p /app/data
    python3 -c '
import wave
import numpy as np
with wave.open("/app/data/recording.wav", "w") as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(44100)
    samples = np.random.randint(-32768, 32767, size=44100*5, dtype=np.int16)
    f.writeframes(samples.tobytes())
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
