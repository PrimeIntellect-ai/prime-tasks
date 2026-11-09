#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/incoming
    mkdir -p /home/user/config_target
    mkdir -p /home/user/config_manager

    cat << 'EOF' > /tmp/setup.py
import os
import zipfile

os.makedirs('/home/user/incoming', exist_ok=True)
os.makedirs('/home/user/config_target', exist_ok=True)

zip_path = '/home/user/incoming/update.zip'

server_conf = 'port=8080\nnaïve=true'.encode('cp1252')
settings_txt = 'café=open\n'.encode('cp1252')
malicious_txt = b'you are hacked'

with zipfile.ZipFile(zip_path, 'w') as z:
    z.writestr('server.conf', server_conf)
    z.writestr('app/settings.txt', settings_txt)
    # Zip slip payload
    z.writestr('../../../../../home/user/pwned.txt', malicious_txt)

# Set permissions
os.chmod(zip_path, 0o644)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
