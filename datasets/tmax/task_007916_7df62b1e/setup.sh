#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip unzip zip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import zipfile

base_dir = '/home/user/backups'
os.makedirs(base_dir, exist_ok=True)

# Safe backup 1
with zipfile.ZipFile(os.path.join(base_dir, 'backup_01.zip'), 'w') as z:
    z.writestr('data/config.txt', 'Safe config data')
    z.writestr('data/logs.txt', 'Safe log data')

# Safe backup 2
with zipfile.ZipFile(os.path.join(base_dir, 'backup_02.zip'), 'w') as z:
    z.writestr('images/pic1.png', 'fake image data')

# Malicious backup (backup_03.zip)
with zipfile.ZipFile(os.path.join(base_dir, 'backup_03.zip'), 'w') as z:
    z.writestr('docs/readme.txt', 'Read me first')
    z.writestr('../../../home/user/.ssh/authorized_keys', 'ssh-rsa AAAAB3Nza... attacker@evil')

# Safe backup 4
with zipfile.ZipFile(os.path.join(base_dir, 'backup_04.zip'), 'w') as z:
    z.writestr('notes.txt', 'Remember to check backups')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
