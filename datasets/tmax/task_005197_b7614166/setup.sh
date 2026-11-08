#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 espeak-ng ffmpeg
pip3 install pytest

mkdir -p /app

cat << 'EOF' > /tmp/setup_db.py
import sqlite3

conn = sqlite3.connect('/app/finance.db')
c = conn.cursor()
c.execute('''CREATE TABLE transfers (tx_id TEXT, from_acct TEXT, to_acct TEXT, amount REAL, tx_date TEXT)''')

edges = [
    ("10001", "10002"),
    ("10001", "10003"),
    ("10002", "10004"),
    ("10003", "10004"),
    ("10004", "10005"),
    ("10005", "10006"),
    ("20001", "20002"),
    ("20002", "20003"),
    ("10006", "10006"),
]

for i, (src, dst) in enumerate(edges):
    c.execute("INSERT INTO transfers VALUES (?, ?, ?, ?, ?)", (f"tx_{i}", src, dst, 100.0, "2024-01-01"))

conn.commit()
conn.close()
EOF
python3 /tmp/setup_db.py

espeak-ng -w /app/whistleblower.wav "The source account is 1 0 0 0 1"

chmod 644 /app/finance.db
chmod 644 /app/whistleblower.wav

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
