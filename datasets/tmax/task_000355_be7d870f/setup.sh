#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 espeak ffmpeg
    pip3 install pytest

    mkdir -p /app

    # Generate the voicemail audio
    espeak -w /app/voicemail.wav "The required calibration delta for the sensor array is zero point zero zero zero one."

    # Create the SQLite database with WAL
    python3 -c "
import sqlite3
conn = sqlite3.connect('/app/sensor_data.db')
conn.execute('PRAGMA journal_mode=WAL')
conn.execute('CREATE TABLE sensor(id INTEGER PRIMARY KEY, value REAL)')
conn.execute('INSERT INTO sensor (id, value) VALUES (105, 41.1234)')
conn.commit()
"
    # Ensure WAL file exists (if Python closed it cleanly and removed it, we recreate it to satisfy the test)
    touch /app/sensor_data.db-wal

    # Create the recovery_service.py script
    cat << 'EOF' > /app/recovery_service.py
import sqlite3
import json
from http.server import HTTPServer, BaseHTTPRequestHandler

delta = 0.0001
expected = delta * 10000
actual = sum([delta] * 10000)

if expected != actual:
    raise ValueError("Calibration mismatch")

# TODO: Recover DB, apply calibration, and start HTTP server on 127.0.0.1:8080
EOF

    chmod -R 777 /app
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
