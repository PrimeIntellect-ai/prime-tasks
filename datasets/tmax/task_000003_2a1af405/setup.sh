#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app

    # Generate the audio file
    espeak -w /app/alert_019.wav "Emergency alert. The affected tenant ID is ALPHA-774. The authorization token to use for the recovery API is BRAVO-992-SECURE."

    # Create the SQLite database
    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

os.makedirs('/app', exist_ok=True)
conn = sqlite3.connect('/app/backup_catalog.db')
c = conn.cursor()
c.execute('''CREATE TABLE backups (
    id INTEGER PRIMARY KEY,
    tenant_id VARCHAR,
    datastore_type VARCHAR,
    file_path VARCHAR,
    backup_timestamp DATETIME,
    size_bytes INTEGER
)''')

backups = [
    (1, 'ALPHA-774', 'postgres', '/backups/pg_1.bak', '2023-10-01T10:00:00Z', 10485760),
    (2, 'ALPHA-774', 'mongo', '/backups/mg_1.archive', '2023-10-02T11:00:00Z', 20971520),
    (3, 'ALPHA-774', 'postgres', '/backups/pg_2.bak', '2023-10-03T12:00:00Z', 15728640),
    (4, 'BETA-111', 'postgres', '/backups/pg_b.bak', '2023-10-03T12:00:00Z', 10000000)
]

c.executemany("INSERT INTO backups VALUES (?, ?, ?, ?, ?, ?)", backups)
conn.commit()
conn.close()
EOF
    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
