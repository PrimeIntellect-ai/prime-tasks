#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import os

db_path = '/home/user/api.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute('CREATE TABLE mocks_v1 (id INTEGER PRIMARY KEY, endpoint TEXT, payload_encoded TEXT)')

# Helper to encode
def encode_payload(status, body):
    s = f"status={status},body={body}"
    return s.encode('utf-16le').hex()

data = [
    (1, "/api/v1/users", encode_payload(200, '{"users": ["alice", "bob"]}')),
    (2, "/api/v1/admin", encode_payload(403, '{"error": "forbidden"}')),
    (3, "/api/v1/health", encode_payload(200, '{"status": "ok"}')),
    (4, "/api/v1/legacy", encode_payload(500, '{"error": "internal error"}'))
]

c.executemany('INSERT INTO mocks_v1 VALUES (?, ?, ?)', data)
conn.commit()
conn.close()

dsl_content = """EXEC /api/v1/users
ASSERT_STATUS 200
EXEC /api/v1/admin
ASSERT_STATUS 200
EXEC /api/v1/health
ASSERT_STATUS 200
EXEC /api/v1/missing
ASSERT_STATUS 404
EXEC /api/v1/legacy
ASSERT_STATUS 500
"""

with open('/home/user/queries.dsl', 'w') as f:
    f.write(dsl_content)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
