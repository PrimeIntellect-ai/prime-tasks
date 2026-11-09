#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/backup_source/machine_1
    mkdir -p /home/user/backup_source/system/bin

    python3 -c "
import os

os.makedirs('/home/user/backup_source/machine_1', exist_ok=True)
os.makedirs('/home/user/backup_source/system/bin', exist_ok=True)

with open('/home/user/backup_source/system/bin/old_service', 'wb') as f:
    f.write(b'\x7f\x45\x4c\x46\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00')

with open('/home/user/backup_source/machine_1/controller', 'wb') as f:
    f.write(b'\x7f\x45\x4c\x46\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00')

content = b'M104 S200 \xb0C ; set temp\nG28 ; home\n\n\nG1 X10 Y10\nM109 S200 ; wait for \xb0C temp\nG1 Z0.2\n' * 5
with open('/home/user/backup_source/machine_1/part.gcode', 'wb') as f:
    f.write(content)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
