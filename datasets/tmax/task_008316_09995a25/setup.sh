#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/incident

    cat << 'EOF' > /home/user/incident/recover.py
import json
import sys

def recover_wal(wal_path, output_path):
    with open(wal_path, 'rb') as f:
        data = f.read()

    if not data.startswith(b'WAL\x01'):
        print("Invalid WAL magic bytes.")
        sys.exit(1)

    records = []
    offset = 4

    # BUG: off-by-one in the boundary check.
    # It should be offset + 4 <= len(data)
    # Because if offset + 4 == len(data), there is exactly a 4-byte length integer left (empty payload),
    # or if the file ends exactly at the end of a payload, offset+4 < len(data) will evaluate to False
    # when checking the length of the LAST record, thus skipping it entirely.
    while offset + 4 < len(data):
        length = int.from_bytes(data[offset:offset+4], 'big')
        offset += 4

        if offset + length > len(data):
            print(f"Warning: Corrupt record at offset {offset}. Truncated.")
            break

        record_bytes = data[offset:offset+length]
        try:
            record_str = record_bytes.decode('utf-8')
            records.append(json.loads(record_str))
        except Exception as e:
            print(f"Error parsing JSON at offset {offset}: {e}")

        offset += length

    with open(output_path, 'w') as f:
        json.dump(records, f, indent=2)

    print(f"Recovered {len(records)} records.")

if __name__ == '__main__':
    recover_wal('db.wal', 'recovered_db.json')
EOF

    cat << 'EOF' > /home/user/incident/generate_wal.py
import json

records = [
    {"action": "USER_LOGIN", "source_ip": "10.0.0.5", "timestamp": "2023-10-01T12:00:00Z"},
    {"action": "DATA_QUERY", "source_ip": "10.0.0.5", "timestamp": "2023-10-01T12:05:00Z"},
    {"action": "SYSTEM_CRASH", "source_ip": "192.168.137.42", "timestamp": "2023-10-01T12:06:13Z"}
]

with open('/home/user/incident/db.wal', 'wb') as f:
    f.write(b'WAL\x01')
    for rec in records:
        payload = json.dumps(rec).encode('utf-8')
        f.write(len(payload).to_bytes(4, 'big'))
        f.write(payload)
EOF

    python3 /home/user/incident/generate_wal.py
    rm /home/user/incident/generate_wal.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
