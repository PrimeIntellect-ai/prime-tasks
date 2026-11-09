#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/project/dump
    mkdir -p /home/user/project/organized

    cat << 'EOF' > /home/user/project/magic.conf
89504e47:textures
cafebabe:objects
504b0304:archives
EOF

    python3 -c "
with open('/home/user/project/dump/file_a.dat', 'wb') as f: f.write(b'\x89\x50\x4E\x47\x00\x01\x02')
with open('/home/user/project/dump/file_b.dat', 'wb') as f: f.write(b'\xCA\xFE\xBA\xBE\x00\x00\x00')
with open('/home/user/project/dump/file_c.dat', 'wb') as f: f.write(b'\x50\x4B\x03\x04\x14\x00\x08')
with open('/home/user/project/dump/file_d.dat', 'wb') as f: f.write(b'\x89\x50\x4E\x47\xFF\xFF\xFF')
with open('/home/user/project/dump/file_unknown.dat', 'wb') as f: f.write(b'\x00\x00\x00\x00\x00\x00\x00')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
