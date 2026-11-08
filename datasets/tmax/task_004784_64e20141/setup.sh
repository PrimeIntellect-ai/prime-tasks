#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-opencv ffmpeg
pip3 install pytest numpy

mkdir -p /app/corpus/clean
mkdir -p /app/corpus/evil

python3 -c '
import cv2
import numpy as np
import random
import os

# Generate video
out = cv2.VideoWriter("/app/storage_dashboard.mp4", cv2.VideoWriter_fourcc(*"mp4v"), 30, (640, 480))
frames = [np.zeros((480, 640, 3), dtype=np.uint8)] * (300 - 43)
red_frame = np.zeros((480, 640, 3), dtype=np.uint8)
red_frame[:] = (0, 0, 255) # BGR format
frames.extend([red_frame] * 43)
random.seed(42)
random.shuffle(frames)
for f in frames:
    out.write(f)
out.release()

# Generate clean corpus
clean_dir = "/app/corpus/clean"
evil_dir = "/app/corpus/evil"

clean_texts = [
    ("clean1.txt", "This is a clean file.", "utf-8"),
    ("clean2.txt", "Another clean file here.", "utf-16"),
    ("clean3.txt", "Clean file ISO.", "iso-8859-1"),
    ("clean4.txt", "Clean file Shift-JIS.", "shift_jis")
]

for name, text, enc in clean_texts:
    with open(os.path.join(clean_dir, name), "wb") as f:
        f.write(text.encode(enc))

evil_texts = [
    ("evil1.txt", "This has ../ path traversal.", "utf-8"),
    ("evil2.txt", "Hidden /etc/passwd file.", "utf-16"),
    ("evil3.txt", "Null byte \x00 inside.", "iso-8859-1"),
    ("evil4.txt", "Another ../ evil.", "shift_jis")
]

for name, text, enc in evil_texts:
    with open(os.path.join(evil_dir, name), "wb") as f:
        f.write(text.encode(enc))
'

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
