#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/logs
    mkdir -p /home/user/data
    mkdir -p /home/user/app

    # Generate Logs
    cat << 'EOF' > /home/user/logs/ingest.log
1715049600|REQ-041|Received payload
1715049605|REQ-042|Received payload
1715049610|REQ-043|Received payload
EOF

    cat << 'EOF' > /home/user/logs/transform.log
2024-05-07T00:00:02Z - REQ-041 - Transformed
2024-05-07T00:00:07Z - REQ-042 - Transformed
2024-05-07T00:00:12Z - REQ-043 - Transformed
EOF

    cat << 'EOF' > /home/user/logs/serialize.log
[05-07-2024 00:00:04] [REQ-041] Processing successful
[05-07-2024 00:00:09] [REQ-042] Processing started
Traceback (most recent call last):
  File "/home/user/app/serializer.py", line 15, in <module>
    serialize(sys.argv[1], sys.argv[2])
  File "/home/user/app/serializer.py", line 10, in serialize
    name_bytes = data['user_name'].encode('ascii')
UnicodeEncodeError: 'ascii' codec can't encode character '\xe9' in position 3: ordinal not in range(128)
[05-07-2024 00:00:14] [REQ-043] Processing successful
EOF

    # Generate Data
    echo '{"user_name": "John Doe", "id": 41}' > /home/user/data/raw_REQ-041.json
    echo '{"user_name": "Jos\u00e9", "id": 42}' > /home/user/data/raw_REQ-042.json
    echo '{"user_name": "Jane Smith", "id": 43}' > /home/user/data/raw_REQ-043.json

    # Generate Broken App
    cat << 'EOF' > /home/user/app/serializer.py
import sys
import json
import struct

def serialize(in_file, out_file):
    with open(in_file, 'r') as f:
        data = json.load(f)

    # Bug: hardcoded ascii, crashes on non-ascii
    name_bytes = data['user_name'].encode('ascii')
    name_padded = name_bytes.ljust(20, b'\x00')

    record_id = data['id']

    with open(out_file, 'wb') as f:
        f.write(struct.pack('<I20s', record_id, name_padded))

if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(1)
    serialize(sys.argv[1], sys.argv[2])
EOF
    chmod +x /home/user/app/serializer.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
