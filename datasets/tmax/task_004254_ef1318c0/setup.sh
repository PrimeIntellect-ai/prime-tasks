#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg libgl1 libglib2.0-0
    pip3 install pytest pandas opencv-python

    mkdir -p /app
    # Generate a 10-second test video at 30fps
    ffmpeg -y -f lavfi -i testsrc=duration=10:size=640x480:rate=30 -pix_fmt yuv420p /app/surveillance.mp4

    # Create the oracle
    cat << 'EOF' > /app/oracle.py
import sys
import csv
import json
import re
import cv2
import math

def run():
    video_path = sys.argv[1]
    users_csv = sys.argv[2]
    events_csv = sys.argv[3]
    output_path = sys.argv[4]

    users = {}
    with open(users_csv, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            users[row['event_id']] = row['username']

    events = {}
    with open(events_csv, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            events[row['event_id']] = row['timestamp_sec']

    cap = cv2.VideoCapture(video_path)
    fps = cap.get(cv2.CAP_PROP_FPS)

    results = []
    for event_id in set(users.keys()).intersection(events.keys()):
        username = users[event_id]
        ts_str = events[event_id]

        if not re.match(r'^[A-Z]{3,4}$', username):
            continue

        try:
            ts = float(ts_str)
        except ValueError:
            continue

        if ts < 0.0 or ts > 10.0:
            continue

        frame_idx = int(ts * fps)
        cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
        ret, frame = cap.read()
        if not ret:
            continue

        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        brightness = math.floor(gray.mean())

        results.append({
            "event_id": event_id,
            "username": username,
            "brightness": brightness
        })

    cap.release()

    results.sort(key=lambda x: x['event_id'])

    with open(output_path, 'w') as f:
        for res in results:
            f.write(json.dumps(res) + "\n")

if __name__ == '__main__':
    run()
EOF
    chmod +x /app/oracle.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
