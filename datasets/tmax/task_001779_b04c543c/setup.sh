#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        libgl1 \
        libglib2.0-0 \
        tesseract-ocr \
        ffmpeg \
        libsm6 \
        libxext6

    pip3 install pytest opencv-python pillow numpy pytesseract

    mkdir -p /app

    cat << 'EOF' > /app/generate_video.py
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

records = [
    "START_RECORD [2023-01-01 10:00:00]\nACTION: APPEND\n[server]\nEND_RECORD",
    "START_RECORD [2023-01-01 10:05:00]\nACTION: APPEND\nport=8080\nEND_RECORD",
    "START_RECORD [2023-01-01 10:10:00]\nACTION: APPEND\nhost=localhost\nEND_RECORD",
    "START_RECORD [2023-01-01 10:15:00]\nACTION: DELETE\n3\nEND_RECORD",
    "START_RECORD [2023-01-01 10:20:00]\nACTION: APPEND\nhost=0.0.0.0\nEND_RECORD",
    "START_RECORD [2023-01-01 10:25:00]\nACTION: APPEND\n[database]\nEND_RECORD",
    "START_RECORD [2023-01-01 10:30:00]\nACTION: APPEND\nurl=sqlite:///db.sqlite\nEND_RECORD",
    "START_RECORD [2023-01-01 10:35:00]\nACTION: APPEND\n[cache]\nEND_RECORD",
    "START_RECORD [2023-01-01 10:40:00]\nACTION: APPEND\nredis_host=127.0.0.1\nEND_RECORD",
    "START_RECORD [2023-01-01 10:45:00]\nACTION: DELETE\n6\nEND_RECORD",
    "START_RECORD [2023-01-01 10:50:00]\nACTION: APPEND\ntemp1\nEND_RECORD",
    "START_RECORD [2023-01-01 10:55:00]\nACTION: APPEND\ntemp2\nEND_RECORD",
    "START_RECORD [2023-01-01 11:00:00]\nACTION: DELETE\n7\nEND_RECORD",
    "START_RECORD [2023-01-01 11:05:00]\nACTION: DELETE\n7\nEND_RECORD",
    "START_RECORD [2023-01-01 11:10:00]\nACTION: APPEND\ntemp3\nEND_RECORD",
    "START_RECORD [2023-01-01 11:15:00]\nACTION: DELETE\n7\nEND_RECORD",
    "START_RECORD [2023-01-01 11:20:00]\nACTION: APPEND\ntemp4\nEND_RECORD",
    "START_RECORD [2023-01-01 11:25:00]\nACTION: DELETE\n7\nEND_RECORD",
    "START_RECORD [2023-01-01 11:30:00]\nACTION: APPEND\ntemp5\nEND_RECORD",
    "START_RECORD [2023-01-01 11:35:00]\nACTION: DELETE\n7\nEND_RECORD"
]

full_text = "\n\n".join(records)
lines = full_text.split('\n')

width, height = 640, 480
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/config_record.mp4', fourcc, 30.0, (width, height))

y_offset = height
line_height = 20

while True:
    img = Image.new('RGB', (width, height), color=(255, 255, 255))
    d = ImageDraw.Draw(img)

    current_y = y_offset
    for line in lines:
        d.text((10, current_y), line, fill=(0, 0, 0))
        current_y += line_height

    frame = np.array(img)
    frame = cv2.cvtColor(frame, cv2.COLOR_RGB2BGR)
    out.write(frame)

    y_offset -= 5
    if current_y < 0:
        break

out.release()
EOF

    python3 /app/generate_video.py
    rm /app/generate_video.py

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/parsed_logs
    chmod -R 777 /home/user
    chmod -R 777 /app
