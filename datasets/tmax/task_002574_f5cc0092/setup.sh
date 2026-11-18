#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg libsm6 libxext6 tesseract-ocr
    pip3 install --no-cache-dir pytest opencv-python-headless numpy pandas

    mkdir -p /app
    cd /app

    cat << 'EOF' > generate_fixtures.py
import sqlite3
import cv2
import numpy as np

# 1. Create SQLite DB
conn = sqlite3.connect('company_data.db')
c = conn.cursor()
c.execute('CREATE TABLE employees (EmpID TEXT, Department TEXT, ClearanceLevel INTEGER)')
c.execute('CREATE TABLE rooms (RoomID TEXT, RequiredClearance INTEGER)')

employees = [
    ('E001', 'Engineering', 3),
    ('E002', 'HR', 1),
    ('E003', 'Security', 5),
    ('E004', 'Janitorial', 2),
    ('E005', 'Management', 4)
]
rooms = [
    ('R101', 1), # Lobby
    ('R102', 2), # Breakroom
    ('R201', 3), # Dev Lab
    ('R301', 5), # Server Room
    ('R401', 4)  # Exec Office
]

c.executemany('INSERT INTO employees VALUES (?,?,?)', employees)
c.executemany('INSERT INTO rooms VALUES (?,?)', rooms)
conn.commit()
conn.close()

# Ground truth access logs
access_logs = [
    ("E001", "R101"), ("E001", "R201"), ("E001", "R301"),
    ("E002", "R101"), ("E002", "R102"),
    ("E003", "R301"), ("E003", "R201"), ("E003", "R101"),
    ("E004", "R101"),
    ("E005", "R401"), ("E005", "R101")
]

# 2. Generate Video
width, height = 640, 480
fps = 1
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('dashboard_leak.mp4', fourcc, fps, (width, height))

for log in access_logs:
    img = np.zeros((height, width, 3), dtype=np.uint8)
    text = f"ACCESS: {log[0]} -> {log[1]}"
    font = cv2.FONT_HERSHEY_SIMPLEX
    cv2.putText(img, text, (50, 240), font, 1.5, (255, 255, 255), 3, cv2.LINE_AA)
    out.write(img)

out.release()

# Generate Ground Truth CSV for Verifier
with open('ground_truth_scores.csv', 'w') as f:
    f.write("EmpID,RiskScore\n")
    f.write("E001,2.0\n")
    f.write("E002,1.5\n")
    f.write("E003,1.5\n")
    f.write("E004,0.5\n")
    f.write("E005,1.0\n")
EOF

    python3 generate_fixtures.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
