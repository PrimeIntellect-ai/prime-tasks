#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang-go
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import struct
import zlib
import os

def write_cba(filename, records):
    with open(filename, 'wb') as f:
        f.write(b'CBA1')
        for rec in records:
            path = rec['path'].encode('utf-8')
            f.write(struct.pack('<H', len(path)))
            f.write(path)
            op = rec['op']
            f.write(struct.pack('<B', op))
            if op == 0:
                data = rec['data'].encode('utf-8')
                compressed = zlib.compress(data)
                f.write(struct.pack('<I', len(compressed)))
                f.write(compressed)

os.makedirs('/home/user/backups', exist_ok=True)
os.makedirs('/home/user/project_workspace', exist_ok=True)

# base.cba
write_cba('/home/user/backups/base.cba', [
    {'path': 'README.md', 'op': 0, 'data': '# Project\nInitial README'},
    {'path': 'src/main.go', 'op': 0, 'data': 'package main\nfunc main() {}'},
])

# inc1.cba
write_cba('/home/user/backups/inc1.cba', [
    {'path': 'README.md', 'op': 0, 'data': '# Project\nUpdated README'},
    {'path': '../../etc/passwd_fake', 'op': 0, 'data': 'malicious payload'},
    {'path': 'src/main.go', 'op': 1},
])

# inc2.cba
write_cba('/home/user/backups/inc2.cba', [
    {'path': 'src/app.go', 'op': 0, 'data': 'package main\n// App'},
    {'path': '/absolute/path/escape.sh', 'op': 0, 'data': 'echo root'},
])
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

chmod -R 777 /home/user
