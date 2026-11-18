#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-opencv python3-numpy
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np
import random
import sqlite3

random.seed(42)
out = cv2.VideoWriter('/app/backup_monitor.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 1, (100, 100))
statuses = []
for i in range(100):
    status = random.choice([0, 1])
    statuses.append(status)
    color = 255 if status == 1 else 0
    frame = np.full((100, 100, 3), color, dtype=np.uint8)
    out.write(frame)
out.release()

def create_oracle_db():
    conn = sqlite3.connect('/app/oracle.db')
    c = conn.cursor()
    c.execute('CREATE TABLE backups (timestamp INTEGER PRIMARY KEY, status INTEGER)')
    for i, s in enumerate(statuses):
        c.execute('INSERT INTO backups VALUES (?, ?)', (1700000000 + i, s))
    conn.commit()
    conn.close()

create_oracle_db()
EOF
    python3 /tmp/gen_video.py

    cat << 'EOF' > /app/oracle_analyzer
#!/usr/bin/env python3
import sys
import sqlite3

t = int(sys.argv[1])
conn = sqlite3.connect('/app/oracle.db')
c = conn.cursor()
query = """
WITH streaks AS (
    SELECT status,
           timestamp,
           timestamp - ROW_NUMBER() OVER (ORDER BY timestamp) as grp
    FROM backups
    WHERE timestamp < ? AND status = 0
)
SELECT IFNULL(MAX(streak_len), 0)
FROM (
    SELECT COUNT(*) as streak_len
    FROM streaks
    GROUP BY grp
)
"""
c.execute(query, (t,))
res = c.fetchone()[0]
print(res)
EOF
    chmod +x /app/oracle_analyzer

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
