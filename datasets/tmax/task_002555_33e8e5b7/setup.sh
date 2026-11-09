#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import os

os.makedirs('/home/user/db_data/partition1', exist_ok=True)
os.makedirs('/home/user/db_data/partition2', exist_ok=True)
os.makedirs('/home/user/db_logs', exist_ok=True)

with open('/home/user/db_data/partition1/001.wal', 'wb') as f:
    f.write(b'\x57\x41\x4c\x01\x12\x04\x00\x00\x99\x88\x77')

with open('/home/user/db_data/partition2/002.wal', 'wb') as f:
    f.write(b'\x57\x41\x4c\x01\x15\x04\x00\x00\xaa\xbb\xcc')

with open('/home/user/db_data/partition2/invalid.wal', 'wb') as f:
    f.write(b'\x57\x41\x4c\x02\x15\x04\x00\x00')

log_content = '''[TX: 1040]
Success
[TX: 1042]
Error: Checkpoint timeout
Retrying flush...
[TX: 1043]
Routine vacuum completed
[TX: 1045]
Warning: disk space low
Archiving forced
'''
with open('/home/user/db_logs/server.log', 'w') as f:
    f.write(log_content)
"

    chown -R user:user /home/user/db_data /home/user/db_logs
    chmod -R 777 /home/user
