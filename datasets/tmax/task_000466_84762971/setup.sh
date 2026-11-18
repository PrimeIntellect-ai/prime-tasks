#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr gcc make file tar gzip
    pip3 install pytest pillow

    cat << 'EOF' > /tmp/setup.py
import os
import struct
import tarfile
from PIL import Image, ImageDraw

# 1. Create image
os.makedirs('/app', exist_ok=True)
img = Image.new('RGB', (400, 100), color='white')
d = ImageDraw.Draw(img)
d.text((10, 40), "ALERT: TARGET VOLUME: VOL-84B IS FULL", fill='red')
img.save('/app/disk_alert.png')

os.makedirs('/app/storage', exist_ok=True)
os.makedirs('/tmp/setup_vols', exist_ok=True)

def make_wal(path, num_records):
    with open(path, 'wb') as f:
        f.write(b'WAL\0')
        f.write(struct.pack('<I', 1)) # Version
        for i in range(num_records):
            # Interleave 0x01 (Data) and 0x03 (Debug)
            rtype = 0x01 if i % 2 == 0 else 0x03
            payload = os.urandom(64)
            f.write(struct.pack('<B', rtype))
            f.write(struct.pack('<I', len(payload)))
            f.write(payload)

def make_elf(path):
    with open(path, 'wb') as f:
        f.write(b'\x7fELF' + os.urandom(128))

# Create dummy VOL-12A
os.makedirs('/tmp/setup_vols/VOL-12A', exist_ok=True)
for i in range(5): make_wal(f'/tmp/setup_vols/VOL-12A/file_{i}.dat', 10)
with tarfile.open('/tmp/setup_vols/VOL-12A.tar.gz', 'w:gz') as tar:
    tar.add('/tmp/setup_vols/VOL-12A', arcname='VOL-12A')

# Create target VOL-84B
os.makedirs('/tmp/setup_vols/VOL-84B', exist_ok=True)
for i in range(10): make_wal(f'/tmp/setup_vols/VOL-84B/data_{i}.bin', 100)
for i in range(5): make_elf(f'/tmp/setup_vols/VOL-84B/exec_{i}.bin')
with tarfile.open('/tmp/setup_vols/VOL-84B.tar.gz', 'w:gz') as tar:
    tar.add('/tmp/setup_vols/VOL-84B', arcname='VOL-84B')

# Pack into backups.tar
with tarfile.open('/app/storage/backups.tar', 'w') as tar:
    tar.add('/tmp/setup_vols/VOL-12A.tar.gz', arcname='VOL-12A.tar.gz')
    tar.add('/tmp/setup_vols/VOL-84B.tar.gz', arcname='VOL-84B.tar.gz')
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
