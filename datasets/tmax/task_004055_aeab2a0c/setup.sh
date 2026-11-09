#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libsndfile1
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate a valid WAV file and CSV corpora
    cat << 'EOF' > /tmp/setup_data.py
import wave
import struct
import os

# Generate valid wav file
with wave.open('/app/recording.wav', 'w') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(16000)
    # Write 1 second of silence/constant
    for i in range(16000):
        data = struct.pack('<h', 0)
        w.writeframesraw(data)

# Clean CSVs
with open('/app/corpus/clean/clean1.csv', 'w') as f:
    f.write("speaker_id,frame_index,feature1,feature2\n")
    f.write("1,10,0.5,0.1\n")
    f.write("2,-5,0.6,0.2\n")
    f.write("100,0,0.7,0.3\n")

# Evil CSVs
with open('/app/corpus/evil/evil1.csv', 'w') as f:
    f.write("speaker_id,frame_index,feature1\n")
    f.write("1.0,10,0.5\n")

with open('/app/corpus/evil/evil2.csv', 'w') as f:
    f.write("speaker_id,frame_index,feature1\n")
    f.write("1,,0.5\n")

with open('/app/corpus/evil/evil3.csv', 'w') as f:
    f.write("speaker_id,frame_index,feature1\n")
    f.write("NaN,10,0.5\n")
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
