#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        tesseract-ocr \
        libtesseract-dev

    pip3 install pytest opencv-python-headless numpy pytesseract networkx

    mkdir -p /app

    # Create video and database
    python3 << 'EOF'
import cv2
import numpy as np
import sqlite3
import os

# Generate video
out = cv2.VideoWriter('/app/robot_tracking.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 1, (640, 480))
waypoints = [12, 45, 18, 92, 31]
for wp in waypoints:
    for _ in range(5):
        frame = np.ones((480, 640, 3), dtype=np.uint8) * 255
        # Draw text
        text = str(wp)
        font = cv2.FONT_HERSHEY_SIMPLEX
        font_scale = 10
        thickness = 15
        text_size = cv2.getTextSize(text, font, font_scale, thickness)[0]
        text_x = (640 - text_size[0]) // 2
        text_y = (480 + text_size[1]) // 2
        cv2.putText(frame, text, (text_x, text_y), font, font_scale, (0, 0, 0), thickness, cv2.LINE_AA)
        out.write(frame)
out.release()

# Generate DB
conn = sqlite3.connect('/app/warehouse.db')
c = conn.cursor()
c.execute('CREATE TABLE nodes (id INTEGER, label TEXT)')
c.execute('CREATE TABLE edges (source_id INTEGER, target_id INTEGER, weight REAL)')
nodes = [(12, 'Node_12'), (45, 'Node_45'), (18, 'Node_18'), (92, 'Node_92'), (31, 'Node_31')]
c.executemany('INSERT INTO nodes VALUES (?, ?)', nodes)
edges = [
    (12, 45, 40.0),
    (45, 18, 35.5),
    (18, 92, 50.0),
    (92, 31, 20.0),
    (45, 31, 42.0)
]
c.executemany('INSERT INTO edges VALUES (?, ?, ?)', edges)
conn.commit()
conn.close()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
