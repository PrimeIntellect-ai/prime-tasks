#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg rustc cargo

    # Set pip timeout and retries to avoid network issues
    pip3 install --default-timeout=100 --retries=5 pytest

    mkdir -p /app

    # Generate the audio file using python and espeak
    cat << 'EOF' > /tmp/generate_audio.py
import random
import os

random.seed(42)
text = ""
for i in range(1, 51):
    fa = round(random.uniform(-2.0, 5.0), 1)
    fb = round(random.uniform(-2.0, 5.0), 1)
    target = round(3.5 * fa - 1.2 * fb + 4.0 + random.gauss(0, 0.5), 1)
    text += f"Row {i}: Feature A {fa}, Feature B {fb}, Target {target}. "

with open("/tmp/dictation.txt", "w") as f:
    f.write(text)

os.system('espeak -w /app/sensor_dictation.wav -f /tmp/dictation.txt')
EOF

    python3 /tmp/generate_audio.py

    # Create test features file
    cat << 'EOF' > /app/test_features.csv
feature_a,feature_b
1.0,1.0
2.5,0.0
-1.0,2.0
4.0,-1.0
0.0,0.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
