#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import zipfile
import json

os.makedirs('/home/user/project_assets', exist_ok=True)

# file_A: Valid zip with metadata.json
with zipfile.ZipFile('/home/user/project_assets/file_A', 'w') as z:
    z.writestr('metadata.json', json.dumps({"asset_id": "A101", "type": "texture", "version": 1.2}))

# file_B: Valid zip with metadata.json
with zipfile.ZipFile('/home/user/project_assets/file_B', 'w') as z:
    z.writestr('metadata.json', json.dumps({"asset_id": "B202", "type": "model", "version": 2.0}))

# file_C: Corrupted zip (starts with magic bytes, but truncated)
with zipfile.ZipFile('/home/user/project_assets/file_C_temp', 'w') as z:
    z.writestr('metadata.json', json.dumps({"asset_id": "C303", "type": "audio", "version": 1.0}))
with open('/home/user/project_assets/file_C_temp', 'rb') as f:
    data = f.read()
with open('/home/user/project_assets/file_C', 'wb') as f:
    f.write(data[:len(data)//2]) # truncate
os.remove('/home/user/project_assets/file_C_temp')

# file_D: Not a zip file (PNG magic bytes)
with open('/home/user/project_assets/file_D', 'wb') as f:
    f.write(b'\x89PNG\r\n\x1a\n' + b'fake_image_data_here')

# file_E: Valid zip, but no metadata.json
with zipfile.ZipFile('/home/user/project_assets/file_E', 'w') as z:
    z.writestr('image.png', b'\x89PNG\r\n\x1a\nfake')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
