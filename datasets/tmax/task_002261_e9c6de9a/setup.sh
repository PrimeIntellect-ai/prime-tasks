#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/app
mkdir -p /home/user/data

cat << 'EOF' > /home/user/app/setup.py
from setuptools import setup

setup(
    name='logparser',
    version='1.0',
    py_modules=['parser']
    install_requires=[
        'pytest'
    ]
)
EOF

cat << 'EOF' > /home/user/app/parser.py
import struct
import sys

def parse_file(filepath):
    with open(filepath, 'rb') as f:
        data = f.read()

    offset = 0
    while offset < len(data):
        record_start = offset
        if offset + 4 > len(data):
            break
        length = struct.unpack('<I', data[offset:offset+4])[0]
        offset += 4

        payload = struct.unpack(f'<{length}s', data[offset:offset+length])[0]
        print(payload.decode('utf-8', errors='ignore'))

        offset += length

if __name__ == '__main__':
    parse_file(sys.argv[1])
EOF

python3 -c "import struct; f=open('/home/user/data/input.bin', 'wb'); f.write(struct.pack('<I', 4) + b'ABCD' + struct.pack('<I', 10) + b'XYZ'); f.close()"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
