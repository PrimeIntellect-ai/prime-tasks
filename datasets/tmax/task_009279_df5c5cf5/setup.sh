#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/ticket_4092
    cd /home/user/ticket_4092

    cat << 'EOF' > processor.py
import json

def deserialize(data: bytes):
    """Deserializes incoming bytes."""
    parts = data.split(b'|', 1)
    if len(parts) < 2:
        return None

    fmt, payload = parts
    if fmt == b'JSON':
        return json.loads(payload.decode('utf-8'))
    elif fmt == b'CUST':
        length_str, rest = payload.split(b'#', 1)
        length = int(length_str)
        text_bytes = rest[:length]
        text = text_bytes.decode('utf-8')
        return text
    return None
EOF

    python3 -c '
import os
import base64
payload = b"CUST|15000#invalid_utf8_\xff"
b64_payload = base64.b64encode(payload).decode("ascii")
dump_data = os.urandom(1024) + f"CRASH_CONTEXT:{b64_payload}".encode("ascii") + os.urandom(1024)
with open("memory.dmp", "wb") as f:
    f.write(dump_data)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
