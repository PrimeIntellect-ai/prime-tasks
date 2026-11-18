#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang ffmpeg
    pip3 install pytest

    mkdir -p /app/corpus/evil /app/corpus/clean

    cat << 'EOF' > /tmp/setup.py
import struct
import binascii
import json
import os

def make_wal_record(payload):
    payload_bytes = payload.encode('utf-8')
    length = len(payload_bytes)
    crc = binascii.crc32(payload_bytes) & 0xffffffff
    return b'WAL1' + struct.pack('<I', length) + payload_bytes + struct.pack('<I', crc)

# Generate WAL
with open('/app/corrupted.wal', 'wb') as f:
    f.write(make_wal_record(json.dumps({"event": "login", "user": "admin"})))
    f.write(b'GARBAGE_DATA_HERE_CORRUPTION')
    f.write(make_wal_record(json.dumps({"event": "logout", "user": "admin"})))
    f.write(b'WAL1' + struct.pack('<I', 100) + b'incomplete...')

# Generate Corpus
for i in range(3):
    with open(f'/app/corpus/clean/{i}.json', 'w') as f:
        json.dump({"auth_token": "a" * 100}, f)

for i in range(3):
    with open(f'/app/corpus/evil/{i}.json', 'w') as f:
        json.dump({"auth_token": "a" * 600}, f)

# Crash log
with open('/app/crash.log', 'w') as f:
    f.write('''panic: runtime error: slice bounds out of range [513:512]

goroutine 1 [running]:
main.processToken(...)
        /app/parser.go:42
main.main()
        /app/main.go:10
''')
EOF

    python3 /tmp/setup.py

    ffmpeg -y -f lavfi -i "color=c=white:s=64x64:r=30:d=10" -vf "drawbox=x=0:y=0:w=64:h=64:color=black:t=fill:enable='between(n,142,187)'" -c:v libx264 -pix_fmt yuv420p /app/incident.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
