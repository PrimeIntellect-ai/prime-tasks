#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-opencv python3-numpy ffmpeg sqlite3
    pip3 install pytest

    mkdir -p /app
    cd /app

    cat << 'EOF' > generate_video.py
import cv2
import numpy as np

width, height = 640, 480
fps = 1
duration = 10
out = cv2.VideoWriter('/app/security_cam.mp4', cv2.VideoWriter_fourcc(*'mp4v'), fps, (width, height))

for t in range(duration):
    if t == 4 or t == 8:
        # Red frame
        frame = np.zeros((height, width, 3), dtype=np.uint8)
        frame[:] = (0, 0, 255) # BGR
    else:
        # Black frame
        frame = np.zeros((height, width, 3), dtype=np.uint8)
    out.write(frame)

out.release()
EOF
    python3 generate_video.py

    cat << 'EOF' > generate_db.py
import sqlite3

conn = sqlite3.connect('/app/compliance.db')
c = conn.cursor()

c.execute('CREATE TABLE employees (emp_id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER)')
c.execute('CREATE TABLE access_logs (id INTEGER PRIMARY KEY, emp_id INTEGER, timestamp INTEGER, resource TEXT)')

# Insert employees (Diana is CEO)
employees = [
    (1, 'Diana', None),
    (2, 'Bob', 1),
    (3, 'Frank', 1),
    (4, 'Alice', 2),
    (5, 'Eve', 3)
]
c.executemany('INSERT INTO employees VALUES (?, ?, ?)', employees)

# Insert access logs
logs = [
    (101, 4, 1730000004, 'MAIN_VAULT'), # Alice at T=4
    (102, 5, 1730000008, 'MAIN_VAULT'), # Eve at T=8
    (103, 2, 1730000001, 'LOBBY')
]
c.executemany('INSERT INTO access_logs VALUES (?, ?, ?, ?)', logs)

# Create the index that they are told is corrupted
c.execute('CREATE INDEX idx_time ON access_logs(timestamp)')
conn.commit()
conn.close()
EOF
    python3 generate_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
