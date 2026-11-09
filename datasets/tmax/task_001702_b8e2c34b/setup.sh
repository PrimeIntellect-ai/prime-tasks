#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak sqlite3
    pip3 install pytest pandas

    mkdir -p /app/telemetry /app/logs /home/user

    # Generate Audio
    espeak -w /app/sysadmin_voicemail.wav "Hey, this is ops. The telemetry server crashed due to a race condition. The DB was writing in local time, Asia/Tokyo, while the system logs are in UTC. I need you to recover the database from the WAL, correlate it with the system logs, and extract all 'CRITICAL' events that happened between 14:00 and 15:00 local time on October 25th, 2023. Put it in a CSV."

    # Generate DB and WAL
    python3 -c "
import sqlite3
import os
import shutil

conn = sqlite3.connect('/app/telemetry/telemetry.db')
conn.execute('PRAGMA journal_mode=WAL')
conn.execute('CREATE TABLE events (id INTEGER PRIMARY KEY, timestamp TEXT, level TEXT, message TEXT)')
conn.execute(\"INSERT INTO events (timestamp, level, message) VALUES ('2023-10-25 14:10:00', 'INFO', 'System started')\")
conn.commit()

# Insert critical event into WAL but don't close to keep WAL around
conn.execute(\"INSERT INTO events (timestamp, level, message) VALUES ('2023-10-25 14:25:00', 'CRITICAL', 'DB crash imminent')\")
conn.commit()

# Copy files while connection is open to preserve the WAL
shutil.copy('/app/telemetry/telemetry.db', '/app/telemetry/telemetry_copy.db')
shutil.copy('/app/telemetry/telemetry.db-wal', '/app/telemetry/telemetry_copy.db-wal')
"
    mv /app/telemetry/telemetry_copy.db /app/telemetry/telemetry.db
    mv /app/telemetry/telemetry_copy.db-wal /app/telemetry/telemetry.db-wal
    rm -f /app/telemetry/telemetry.db-shm

    # Generate Syslog
    cat << 'EOF' > /app/logs/syslog.log
{"timestamp": "2023-10-25T05:20:00Z", "level": "INFO", "message": "All systems nominal"}
{"timestamp": "2023-10-25T05:30:00Z", "level": "Q1JJVElDQUw=", "message": "U3lzbG9nIGNyYXNoIGRldGVjdGVk"}
EOF

    # Generate Ground Truth CSV
    cat << 'EOF' > /app/ground_truth.csv
timestamp_utc,source,message
2023-10-25T05:25:00Z,db,DB crash imminent
2023-10-25T05:30:00Z,syslog,Syslog crash detected
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
