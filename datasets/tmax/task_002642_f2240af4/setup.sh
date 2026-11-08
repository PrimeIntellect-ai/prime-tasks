#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ ffmpeg
pip3 install pytest gTTS

cat << 'EOF' > /tmp/setup.py
import os
from gtts import gTTS
import subprocess

os.makedirs("/app/audio", exist_ok=True)
os.makedirs("/app/corpora/clean", exist_ok=True)
os.makedirs("/app/corpora/evil", exist_ok=True)

text = "The corrupted graphs all contain directed cycles. Filter them out. The clean graphs are strict directed acyclic graphs."
tts = gTTS(text)
tts.save("/tmp/notes.mp3")
subprocess.run(["ffmpeg", "-y", "-i", "/tmp/notes.mp3", "-ar", "16000", "/app/audio/lab_notes.wav"], check=True)

# Clean graph 001 - DAG, node 73 has highest total degree
with open("/app/corpora/clean/graph_001.txt", "w") as f:
    f.write("73 1\n73 2\n73 3\n73 4\n73 5\n73 6\n73 7\n73 8\n73 9\n73 10\n1 2\n")

with open("/app/corpora/clean/graph_002.txt", "w") as f:
    f.write("1 2\n1 3\n2 4\n3 4\n")

# Evil graphs - contain directed cycles
with open("/app/corpora/evil/evil_001.txt", "w") as f:
    f.write("1 2\n2 3\n3 1\n")

with open("/app/corpora/evil/evil_002.txt", "w") as f:
    f.write("10 20\n20 30\n30 40\n40 20\n")
EOF

python3 /tmp/setup.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
