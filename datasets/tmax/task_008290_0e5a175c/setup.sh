#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/workspace

    cat << 'EOF' > /tmp/setup_data.py
import json
import base64
import zlib
import os

os.makedirs('/home/user/data', exist_ok=True)
with open('/home/user/data/webhooks.jsonl', 'w') as f:
    for i in range(1, 1001):
        # Generate some dummy payload
        data = f"analytics_event_payload_{i}_" * (i % 10 + 1)
        data_bytes = data.encode('utf-8')

        encoded = base64.b64encode(data_bytes).decode('utf-8')
        actual_crc = zlib.crc32(data_bytes) & 0xffffffff

        # Corrupt every 3rd and 7th payload to simulate invalid checksums
        if i % 3 == 0 or i % 7 == 0:
            crc_to_write = actual_crc ^ 0xFF
        else:
            crc_to_write = actual_crc

        record = {
            "id": i,
            "encoded_data": encoded,
            "checksum": crc_to_write
        }
        f.write(json.dumps(record) + '\n')
EOF

    python3 /tmp/setup_data.py

    chmod -R 777 /home/user
