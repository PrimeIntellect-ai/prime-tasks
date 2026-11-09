#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git sqlite3 ffmpeg libsm6 libxext6
    pip3 install pytest opencv-python-headless numpy flask

    mkdir -p /app/video_service/db

    # Create the test video
    cat << 'EOF' > /tmp/make_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/test_video.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (100, 100))
for i in range(150):
    if i in [45, 90, 135]:
        frame = np.zeros((100, 100, 3), dtype=np.uint8)
        frame[:, :] = (0, 0, 255) # BGR
    else:
        frame = np.zeros((100, 100, 3), dtype=np.uint8)
    out.write(frame)
out.release()
EOF
    python3 /tmp/make_video.py

    # Create DB and WAL
    cat << 'EOF' > /tmp/make_db.py
import sqlite3
import os

conn = sqlite3.connect('/app/video_service/db/settings.db')
conn.execute('PRAGMA journal_mode=WAL;')
conn.execute('CREATE TABLE thresholds (id INTEGER PRIMARY KEY, color TEXT, min_r INTEGER);')
conn.execute("INSERT INTO thresholds (id, color, min_r) VALUES (1, 'red', 200);")
conn.commit()
os._exit(0) # Exit without closing to keep WAL file
EOF
    python3 /tmp/make_db.py

    # Corrupt DB
    dd if=/dev/urandom of=/app/video_service/db/settings.db bs=1024 count=4

    # Create analyzer.py
    cat << 'EOF' > /app/video_service/analyzer.py
import cv2

def analyze_video(video_path):
    cap = cv2.VideoCapture(video_path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    events = []
    frame_index = 0
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        b, g, r = cv2.split(frame)
        if r.mean() > 200 and g.mean() < 50 and b.mean() < 50:
            timestamp = int(frame_index / fps)
            events.append(timestamp)
        frame_index += 1
    return events
EOF

    # Create start.sh
    cat << 'EOF' > /app/video_service/start.sh
#!/bin/bash
export FLASK_APP=server.py
flask run --host=127.0.0.1 --port=8080
EOF
    chmod +x /app/video_service/start.sh

    # Create server.py
    cat << 'EOF' > /app/video_service/server.py
from flask import Flask, request, jsonify
import json
from analyzer import analyze_video

app = Flask(__name__)

@app.route('/api/events')
def events():
    with open('config.json') as f:
        config = json.load(f)
    auth = request.headers.get('Authorization')
    if auth != f"Bearer {config.get('api_secret')}":
        return "Unauthorized", 401

    events = analyze_video('/app/test_video.mp4')
    return jsonify({"events": events})
EOF

    # Setup git repo
    cd /app/video_service
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    echo '{"api_secret": "sec_99abf210d"}' > config.json
    git add config.json analyzer.py start.sh server.py
    git commit -m "Initial commit"

    echo '{"api_secret": "REDACTED"}' > config.json
    git add config.json
    git commit -m "Remove secret"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
