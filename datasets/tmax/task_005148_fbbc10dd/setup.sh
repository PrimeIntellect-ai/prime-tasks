#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest

mkdir -p /home/user/backups

cat << 'EOF' > /home/user/setup_backups.py
import struct
import os

def create_bak(filename, entries):
    with open(filename, 'wb') as f:
        f.write(b'BAK1')
        f.write(struct.pack('<I', len(entries)))
        for path, data in entries:
            path_bytes = path.encode('utf-8')
            f.write(struct.pack('<H', len(path_bytes)))
            f.write(path_bytes)
            f.write(struct.pack('<I', len(data)))
            f.write(data)

os.makedirs('/home/user/backups', exist_ok=True)

# Safe backup
create_bak('/home/user/backups/safe1.bak', [
    ('docs/readme.txt', b'Hello World'),
    ('images/cat.png', b'FAKE_PNG_DATA')
])

# Malicious backup 1 (Absolute paths)
create_bak('/home/user/backups/malicious_abs.bak', [
    ('local_file.txt', b'Safe data'),
    ('/etc/shadow', b'root:!:12345:0:99999:7:::'),
    ('/root/.ssh/authorized_keys', b'ssh-rsa AAAAB3...')
])

# Malicious backup 2 (Relative traversal)
create_bak('/home/user/backups/malicious_rel.bak', [
    ('config.json', b'{"set": 1}'),
    ('../../.bashrc', b'alias ls=rm'),
    ('folder/../../usr/bin/python', b'fake binary')
])

# Invalid backup (wrong magic bytes)
with open('/home/user/backups/invalid.bak', 'wb') as f:
    f.write(b'ZIP0')
    f.write(b'\x00\x00\x00\x00')

EOF

python3 /home/user/setup_backups.py
rm /home/user/setup_backups.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
