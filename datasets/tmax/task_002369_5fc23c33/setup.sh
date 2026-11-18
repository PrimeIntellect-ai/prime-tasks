#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pillow

    mkdir -p /app

    # Create the legacy spec image
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), 'RAS Magic Header: 0x52 0x41 0x53 0x0A', fill=(0, 0, 0))
img.save('/app/legacy_spec.png')
"

    # Create the oracle extractor
    cat << 'EOF' > /app/oracle_extractor.py
import sys
import zlib
import struct

def main():
    data = sys.stdin.buffer.read()
    magic = b'RAS\n'
    idx = 0
    while idx < len(data):
        pos = data.find(magic, idx)
        if pos == -1:
            break

        chunk_start = pos + 4
        if chunk_start + 4 > len(data):
            idx = pos + 1
            continue

        length = struct.unpack('<I', data[chunk_start:chunk_start+4])[0]
        payload_start = chunk_start + 4
        payload_end = payload_start + length

        if payload_end + 4 > len(data):
            idx = pos + 1
            continue

        payload = data[payload_start:payload_end]
        checksum = struct.unpack('<I', data[payload_end:payload_end+4])[0]

        try:
            uncompressed = zlib.decompress(payload)
        except zlib.error:
            idx = pos + 1
            continue

        if zlib.crc32(uncompressed) != checksum:
            idx = pos + 1
            continue

        try:
            text = uncompressed.decode('utf-8')
        except UnicodeDecodeError:
            idx = pos + 1
            continue

        lines = text.split('\n', 1)
        if not lines[0].startswith('Title: '):
            idx = pos + 1
            continue

        doc_name = lines[0][7:].strip()
        rest = lines[1] if len(lines) > 1 else ""

        sys.stdout.write(f"=== {doc_name}.txt ===\n{rest}\n---DOC---\n")

        idx = payload_end + 4

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
