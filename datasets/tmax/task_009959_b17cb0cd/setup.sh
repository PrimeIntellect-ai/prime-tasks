#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user/service/data

    # Create the SQLite DB
    sqlite3 /home/user/service/data/records.db <<EOF
CREATE TABLE records (id INTEGER PRIMARY KEY, metadata TEXT);
INSERT INTO records (id, metadata) VALUES (1, '{"status": "active", "tier": "premium"}');
INSERT INTO records (id, metadata) VALUES (2, '{"status": "inactive", "tier": "free"}');
INSERT INTO records (id, metadata) VALUES (3, '{"status": "active", "tier": "standard"}');
EOF

    # Create the flawed query_engine.py
    cat << 'EOF' > /home/user/service/query_engine.py
import sqlite3

def get_record_metadata(db_path, record_id):
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    # Bad query fetching everything into memory
    c.execute("SELECT id, metadata FROM records")
    all_records = c.fetchall()
    for row in all_records:
        if row[0] == record_id:
            conn.close()
            return row[1]
    conn.close()
    return None
EOF

    # Create the original serializer.py
    cat << 'EOF' > /home/user/service/serializer_source.py
import base64
import json

_decode_cache = {}

def deserialize(payload):
    if payload in _decode_cache:
        return _decode_cache[payload]

    # Custom decoding logic
    decoded = base64.b64decode(payload).decode('utf-8')
    parsed = json.loads(decoded)

    _decode_cache[payload] = parsed
    return parsed
EOF

    # Compile to pyc and remove source
    python3 -m py_compile /home/user/service/serializer_source.py
    mv /home/user/service/__pycache__/serializer_source.*.pyc /home/user/service/serializer.pyc
    rm /home/user/service/serializer_source.py

    # Create main.py
    cat << 'EOF' > /home/user/service/main.py
import sys
import json
import tracemalloc
import serializer
import query_engine

def process_data():
    payloads = [
        b'eyJ1c2VyX2lkIjogMSwgImFjdGlvbiI6ICJsb2dpbiJ9',
        b'eyJ1c2VyX2lkIjogMiwgImFjdGlvbiI6ICJsb2dvdXQifQ==',
        b'eyJ1c2VyX2lkIjogMywgImFjdGlvbiI6ICJ1cGRhdGUifQ=='
    ] * 1000  # simulate streaming data

    results = []
    for p in payloads:
        data = serializer.deserialize(p)
        meta = query_engine.get_record_metadata('/home/user/service/data/records.db', data['user_id'])
        if meta:
            data['metadata'] = json.loads(meta)
        results.append(data)

    with open('/home/user/service/output.json', 'w') as f:
        json.dump(results[:3], f) # Just dump first 3 for validation

if __name__ == "__main__":
    if "--run" in sys.argv:
        tracemalloc.start()
        process_data()
        current, peak = tracemalloc.get_traced_memory()
        tracemalloc.stop()
        if peak > 10 * 1024 * 1024:
            print(f"Memory limit exceeded: {peak / 1024 / 1024:.2f} MB")
            sys.exit(1)
        print("Success")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
