#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        sqlite3 \
        ffmpeg \
        fonts-dejavu-core

    pip3 install pytest flask fastapi uvicorn requests

    mkdir -p /app

    # Generate the incident record video
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=5 \
        -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='Missing FK\: backups.device_ref_hash = devices.hw_id':fontcolor=white:fontsize=24:x=10:y=100,drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='API_TOKEN\: DBRE_SECURE_8832':fontcolor=white:fontsize=24:x=10:y=150" \
        -y /app/incident_record.mp4

    # Setup the SQLite database
    sqlite3 /app/backup_inventory.sqlite <<EOF
CREATE TABLE devices (id INTEGER PRIMARY KEY, hw_id TEXT, device_name TEXT);
INSERT INTO devices (hw_id, device_name) VALUES ('abc', 'Server-A'), ('def', 'Server-B');
CREATE TABLE backups (id INTEGER PRIMARY KEY, device_ref_hash TEXT, status TEXT, timestamp DATETIME);
INSERT INTO backups (device_ref_hash, status, timestamp) VALUES ('abc', 'FAILED', '2023-10-01 10:00:00');
INSERT INTO backups (device_ref_hash, status, timestamp) VALUES ('abc', 'SUCCESS', '2023-10-02 10:00:00');
INSERT INTO backups (device_ref_hash, status, timestamp) VALUES ('def', 'SUCCESS', '2023-10-01 11:00:00');
CREATE INDEX idx_backups_ts ON backups(timestamp);
EOF

    # Intentionally corrupt the index
    sqlite3 /app/backup_inventory.sqlite <<EOF
PRAGMA writable_schema=ON;
UPDATE sqlite_master SET sql = 'CREATE INDEX idx_backups_ts ON backups(status)' WHERE name='idx_backups_ts';
PRAGMA writable_schema=OFF;
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
