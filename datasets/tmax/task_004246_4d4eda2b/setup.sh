#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest flask fastapi uvicorn requests

    mkdir -p /app

    # Generate WAL file
    cat << 'EOF' > /tmp/gen_wal.py
import struct
import os

os.makedirs('/app', exist_ok=True)
wal_path = '/app/db_system.wal'

records = [
    (1700000000, 0x01, b"Server started"),
    (1700000010, 0x02, b"High memory usage"),
    (1700000015, 0x03, b"OOM Killer invoked"),
    (1700000020, 0x01, b"Restarting service"),
    (1700000025, 0x03, b"Disk write failure sector 8")
]

with open(wal_path, 'wb') as f:
    for ts, rtype, payload in records:
        f.write(struct.pack('>Q B I', ts, rtype, len(payload)))
        f.write(payload)
EOF
    python3 /tmp/gen_wal.py

    # Generate 25-second video using ffmpeg
    ffmpeg -y -f lavfi -i testsrc=duration=25:size=320x240:rate=10 -c:v libx264 -preset ultrafast /app/server_room_cam.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
