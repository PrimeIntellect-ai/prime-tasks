#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest opencv-python-headless

    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /tmp/setup.py
import cv2
import numpy as np
import sqlite3
import os

# Create Video
out = cv2.VideoWriter('/app/warehouse_traffic.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (64, 64))
black_frames = 0
for i in range(100):
    if i % 7 == 0 and black_frames < 14:
        frame = np.zeros((64, 64, 3), dtype=np.uint8)
        black_frames += 1
    else:
        frame = np.ones((64, 64, 3), dtype=np.uint8) * 255
    out.write(frame)
out.release()

# Create DB
conn = sqlite3.connect('/app/warehouse.db')
c = conn.cursor()
c.execute('CREATE TABLE edges (source TEXT, target TEXT, weight INTEGER)')
edges = [
    ('A', 'C', 2),
    ('C', 'D', 1),
    ('D', 'F', 2),
    ('A', 'B', 5),
    ('B', 'E', 5),
    ('E', 'F', 5)
]
c.executemany('INSERT INTO edges VALUES (?,?,?)', edges)
conn.commit()
conn.close()

# Create Corpus
for i in range(20):
    with open(f'/app/corpus/clean/query_{i}.sql', 'w') as f:
        f.write('SELECT * FROM users WHERE id = ?;\n')
    with open(f'/app/corpus/evil/query_{i}.sql', 'w') as f:
        f.write("SELECT * FROM users WHERE username = 'admin' OR 1=1;\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
