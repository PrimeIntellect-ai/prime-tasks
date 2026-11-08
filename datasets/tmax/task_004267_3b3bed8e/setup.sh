#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create the SQLite database
    sqlite3 beacon.db <<EOF
CREATE TABLE beacons (id INTEGER, timestamp INTEGER, key REAL, flag TEXT);
INSERT INTO beacons VALUES (123, 1700000000, 1.000000005, 'FLAG{fL0at1ng_p0int_f0r3ns1cs_M4st3r}');
EOF

    # Create syslog.log
    cat << 'EOF' > syslog.log
1700000000 INFO Payload: eyJpZCI6IDEyMywgIngiOiAxZS0wOH0
EOF

    # Create broken analyze.py
    cat << 'EOF' > analyze.py
import base64
import json
import sqlite3
import math
import re

def decode_payload(b64_str):
    # BUG 1: Fails on missing base64 padding
    decoded = base64.b64decode(b64_str)
    return json.loads(decoded.decode('utf-8'))

def compute_key(x):
    # BUG 2: Numerical instability for very small x (math.exp(x) - 1.0 yields 0 or inaccurate results)
    # The correct stable formula uses math.expm1(x)
    return (math.exp(x) - 1.0) / x if x != 0 else 1.0

def find_flag(db_path, payload_id, key):
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    # BUG 3: Exact float equality match fails
    c.execute("SELECT flag FROM beacons WHERE id = ? AND key = ?", (payload_id, key))
    row = c.fetchone()
    return row[0] if row else None

def main():
    with open('syslog.log', 'r') as f:
        log_line = f.read().strip()

    timestamp = int(log_line.split(' ')[0])
    b64_payload = log_line.split(' ')[2]

    payload = decode_payload(b64_payload)
    key = compute_key(payload['x'])

    flag = find_flag('beacon.db', payload['id'], key)

    if flag:
        with open('flag.txt', 'w') as f:
            f.write(flag)
            print("Flag successfully written to flag.txt")
    else:
        print("Flag not found.")

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
