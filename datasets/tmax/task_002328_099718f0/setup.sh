#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg r-base
    pip3 install pytest opencv-python-headless numpy

    mkdir -p /app/training_corpus/clean /app/training_corpus/evil
    mkdir -p /app/test_corpus/clean /app/test_corpus/evil

    cat << 'EOF' > /tmp/generate_data.py
import cv2
import numpy as np
import os
import random

# Generate video
out = cv2.VideoWriter('/app/experiment_record.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (640, 480))
for i in range(120):
    if (10 <= i <= 15) or (45 <= i <= 50) or (90 <= i <= 95):
        frame = np.zeros((480, 640, 3), dtype=np.uint8)
    else:
        frame = np.random.randint(0, 256, (480, 640, 3), dtype=np.uint8)
    out.write(frame)
out.release()

# Generate text
def make_texts(base_dir, clean_count, evil_count):
    clean_sentences = ["The participant raised their left hand.", "Data analysis is important.", "We collected the survey results.", "The experiment was a success.", "Please review the attached document."]
    for i in range(clean_count):
        with open(os.path.join(base_dir, 'clean', f'file_{i}.txt'), 'w') as f:
            f.write(random.choice(clean_sentences) + " " + random.choice(clean_sentences))

    for i in range(evil_count):
        with open(os.path.join(base_dir, 'evil', f'file_{i}.txt'), 'w') as f:
            text = random.choice(clean_sentences) + " " + random.choice(clean_sentences)
            text += " ;" * 20 + "!" * 15 + "?" * 10
            f.write(text)

make_texts('/app/training_corpus', 20, 20)
make_texts('/app/test_corpus', 50, 50)
EOF

    python3 /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
