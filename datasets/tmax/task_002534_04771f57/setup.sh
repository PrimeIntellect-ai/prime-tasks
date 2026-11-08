#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg tesseract-ocr sqlite3 netcat-openbsd fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=10 -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='CORRUPT':enable='between(t,3,4)+between(t,8,9)':x=100:y=100:fontsize=48:fontcolor=white" -c:v libx264 /app/backup_run.mp4
    chmod -R 777 /app

    mkdir -p /home/user
    sqlite3 /home/user/backups.db <<EOF
CREATE TABLE nodes (job_id INTEGER PRIMARY KEY, status TEXT);
CREATE TABLE edges (source_id INTEGER, target_id INTEGER);
INSERT INTO nodes VALUES (1, 'OK'), (2, 'OK'), (3, 'CORRUPT'), (4, 'OK'), (5, 'OK'), (8, 'CORRUPT'), (9, 'OK'), (10, 'OK');
INSERT INTO edges VALUES (1, 2), (3, 4), (4, 5), (8, 9), (9, 10), (2, 5);
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
