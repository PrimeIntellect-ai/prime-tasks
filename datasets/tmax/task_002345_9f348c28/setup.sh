#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/project_files

    cat << 'EOF' > /home/user/setup_files.py
import base64
import os

files = {
    "f1.enc": "10 + 20",
    "f2.enc": "f1.enc * 2",
    "f3.enc": "f2.enc - f1.enc",
    "c1.enc": "c2.enc + 1",
    "c2.enc": "c1.enc + 1",
    "c3.enc": "c1.enc * 5",
    "deep1.enc": "1",
    "deep2.enc": "deep1.enc + 1",
    "deep3.enc": "deep2.enc + 1",
    "deep4.enc": "deep3.enc + 1",
    "deep5.enc": "deep4.enc + 1"
}

os.makedirs("/home/user/project_files", exist_ok=True)
for fname, content in files.items():
    encoded = base64.b64encode(content.encode('utf-8')).decode('utf-8')
    with open(f"/home/user/project_files/{fname}", "w") as f:
        f.write(encoded)
EOF

    python3 /home/user/setup_files.py
    rm /home/user/setup_files.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
