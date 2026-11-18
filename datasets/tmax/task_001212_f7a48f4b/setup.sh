#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/backup.conf
.log
.txt
EOF

    python3 -c "
import struct

def create_entry(filename, data):
    filename_bytes = filename.encode('ascii')
    header = b'BKUP' + struct.pack('<H', len(filename_bytes)) + filename_bytes + struct.pack('<I', len(data))
    return header + data

with open('/home/user/raw_data.bin', 'wb') as f:
    f.write(create_entry('system.log', b'SYSTEM LOG DATA 10101010\n'))
    f.write(create_entry('picture.png', b'\x89PNG\r\n\x1a\n...fake png data...'))
    f.write(create_entry('auth.log', b'AUTH LOG DATA 20202020\n'))
    f.write(create_entry('notes.txt', b'IMPORTANT NOTES\n'))
    f.write(create_entry('video.mp4', b'fake video data'))
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
