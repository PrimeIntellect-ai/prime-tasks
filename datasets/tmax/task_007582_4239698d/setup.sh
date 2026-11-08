#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git sqlite3
pip3 install pytest

# Setup directories
mkdir -p /home/user/worker_repo
mkdir -p /home/user/data
cd /home/user

# 1. Git Repository Setup
cd /home/user/worker_repo
git init
git config user.name "Oncall"
git config user.email "oncall@example.com"
echo "print('Hello World')" > main.py
git add main.py
git commit -m "Initial commit"

echo "SECRET_KEY = 'zulu_tango_99'" > config.py
git add config.py
git commit -m "Add config with keys"

rm config.py
echo "import os" > config.py
echo "SECRET_KEY = os.environ.get('SECRET_KEY')" >> config.py
git add config.py
git commit -m "Remove hardcoded secret key"

# 2. Memory Dump Setup
cd /home/user
dd if=/dev/urandom of=worker_dump.bin bs=1K count=1024 2>/dev/null
echo -n '...junk... CRASH_CONTEXT: {"last_event_id": "evt_88421_crash", "tz_offset": "+0500"} ...junk...' >> worker_dump.bin
dd if=/dev/urandom bs=1K count=100 >> worker_dump.bin 2>/dev/null

# 3. Corrupted Payload Setup
cat << 'EOF' > /tmp/make_payload.py
import json

key = b'zulu_tango_99'
payload = b'{"event":"telemetry", "timestamp":"2023-10-27T03:14:05\xff\xfe", "data":"critical"}'

encrypted = bytearray()
for i, b in enumerate(payload):
    encrypted.append(b ^ key[i % len(key)])

with open('/home/user/corrupt_payload.enc', 'wb') as f:
    f.write(encrypted)
EOF
python3 /tmp/make_payload.py
rm /tmp/make_payload.py

# 4. Database Recovery Setup
cd /home/user/data
cat << 'EOF' > /tmp/make_db.py
import sqlite3
import os

conn = sqlite3.connect('events_temp.db')
conn.execute('PRAGMA journal_mode=WAL')
conn.execute('CREATE TABLE processed_events (id INTEGER PRIMARY KEY, status TEXT)')
conn.executemany("INSERT INTO processed_events (status) VALUES (?)", [('ok',)] * 7)
conn.commit()

conn.execute('PRAGMA wal_checkpoint(TRUNCATE)')

conn.executemany("INSERT INTO processed_events (status) VALUES (?)", [('pending',)] * 3)
conn.commit()

# Hard exit to leave WAL uncheckpointed
os._exit(0)
EOF
python3 /tmp/make_db.py
rm /tmp/make_db.py

mv events_temp.db events.db
mv events_temp.db-wal events.db-wal
if [ -f events_temp.db-shm ]; then mv events_temp.db-shm events.db-shm; fi

# Corrupt the main DB file by zeroing the first 100 bytes (header)
dd if=/dev/zero of=events.db bs=100 count=1 conv=notrunc 2>/dev/null

# Create user
useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
