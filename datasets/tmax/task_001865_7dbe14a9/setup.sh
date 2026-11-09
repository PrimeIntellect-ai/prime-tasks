#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang espeak-ng ffmpeg sqlite3
    pip3 install pytest

    mkdir -p /app

    # Generate the audio file
    espeak-ng -w /app/audit_recording.wav "The incident occurred on SERVER-82. I repeat, SERVER-82."

    # Create the database and corrupt the index
    cat << 'EOF' > /tmp/setup_db.py
import sqlite3

conn = sqlite3.connect('/app/compliance.db')
c = conn.cursor()

# Create tables
c.execute("CREATE TABLE access_logs (id INTEGER, server_name TEXT, user_id TEXT, timestamp INTEGER)")
c.execute("CREATE TABLE kg_edges (subject TEXT, predicate TEXT, object TEXT)")

# Create a dummy table and index to steal its empty rootpage
c.execute("CREATE TABLE dummy (server_name TEXT)")
c.execute("CREATE INDEX idx_dummy ON dummy(server_name)")

# Insert ground truth data
c.execute("INSERT INTO access_logs VALUES (1, 'SERVER-82', 'U-909', 1672531100)")
c.execute("INSERT INTO access_logs VALUES (2, 'SERVER-82', 'U-112', 1672540000)")
c.execute("INSERT INTO access_logs VALUES (3, 'SERVER-82', 'U-AUTH', 1672550000)")
c.execute("INSERT INTO access_logs VALUES (4, 'SERVER-99', 'U-909', 1672531100)")

c.execute("INSERT INTO kg_edges VALUES ('U-AUTH', 'CAN_ACCESS', 'SERVER-82')")
c.execute("INSERT INTO kg_edges VALUES ('U-112', 'CAN_ACCESS', 'SERVER-99')")

# Corrupt the index by pointing idx_server to the empty idx_dummy b-tree
c.execute("PRAGMA writable_schema = ON")
c.execute("UPDATE sqlite_master SET name='idx_server', tbl_name='access_logs', sql='CREATE INDEX idx_server ON access_logs(server_name)' WHERE name='idx_dummy'")
c.execute("DELETE FROM sqlite_master WHERE name='dummy'")

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
