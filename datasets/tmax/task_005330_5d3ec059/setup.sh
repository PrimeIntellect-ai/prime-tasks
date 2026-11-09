#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import json
import base64
import os

logs = [
    {"request_id": 101, "encoded_filename": base64.b64encode(b"profile_pic.jpg").decode()},
    {"request_id": 102, "encoded_filename": base64.b64encode(b"../../etc/shadow").decode()},
    {"request_id": 103, "encoded_filename": base64.b64encode(b"document_final.pdf").decode()},
    {"request_id": 104, "encoded_filename": base64.b64encode(b"uploads/..\\..\\windows\\system32\\config\\sam").decode()},
    {"request_id": 105, "encoded_filename": base64.b64encode(b"safe_file_..txt").decode()},
    {"request_id": 106, "encoded_filename": base64.b64encode(b"image.png").decode()},
    {"request_id": 107, "encoded_filename": base64.b64encode(b"var/www/html/../../../etc/passwd").decode()}
]

os.makedirs("/home/user", exist_ok=True)
with open("/home/user/upload_logs.json", "w") as f:
    json.dump(logs, f, indent=2)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
