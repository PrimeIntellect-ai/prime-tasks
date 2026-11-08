#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip rustc
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/data/subdir
mkdir -p /home/user/backups

ln -s /home/user/data /home/user/data/subdir/loop

# Create the binary backup file using Python to ensure correct byte formatting
python3 -c "
import struct
import os
with open('/home/user/backups/latest.bak', 'wb') as f:
    f.write(b'BAK1')
    f.write(struct.pack('<I', 27))
    f.write(b'/home/user/data/subdir/loop')
    f.write(b'\x00\x01\x02\x03\x04\x05')
    f.write(os.urandom(1024*1024))
"

chmod -R 777 /home/user
