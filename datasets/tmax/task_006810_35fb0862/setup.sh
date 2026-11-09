#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import os
import struct

os.makedirs('/home/user/logs', exist_ok=True)

data = {
    'log.0': [
        '2023-10-01T10:00:00Z,INFO,Backup service started',
        '2023-10-01T10:05:00Z,DEBUG,Scanning directories',
    ],
    'log.1': [
        '2023-10-01T10:10:00Z,WARN,File locked by another process',
        '2023-10-01T10:15:00Z,INFO,Retrying locked file',
    ],
    'log.2': [
        '2023-10-01T10:20:00Z,ERROR,Failed to backup file',
    ],
    'active.log': [
        '2023-10-01T10:25:00Z,INFO,Backup service shutting down',
    ]
}

for filename, records in data.items():
    filepath = os.path.join('/home/user/logs', filename)
    with open(filepath, 'wb') as f:
        for record in records:
            payload = record.encode('utf-8')
            f.write(struct.pack('>I', len(payload)))
            f.write(payload)
"

    chmod -R 777 /home/user
