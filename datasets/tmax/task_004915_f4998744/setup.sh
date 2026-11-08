#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow pytesseract

    mkdir -p /app

    # Generate the backup specs image
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = 'Legacy Backup Specs:\nMagic Bytes: 0x7B3F\nChecksum Salt: 559102'
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/backup_specs.png')
"

    # Create the oracle script
    cat << 'EOF' > /app/oracle_parse_dump
#!/usr/bin/env python3
import sys
import mmap
import struct
import json
import zlib
import csv
import os

def main():
    if len(sys.argv) < 2:
        sys.exit(1)
    filename = sys.argv[1]

    if not os.path.exists(filename) or os.path.getsize(filename) == 0:
        writer = csv.writer(sys.stdout)
        writer.writerow(["file_id", "path", "symlink_target"])
        sys.exit(0)

    magic = b'\x7b\x3f'
    salt = b'559102'

    writer = csv.writer(sys.stdout)
    writer.writerow(["file_id", "path", "symlink_target"])

    try:
        with open(filename, "rb") as f:
            mm = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
            pos = 0
            while True:
                pos = mm.find(magic, pos)
                if pos == -1:
                    break

                if pos + 6 > len(mm):
                    break

                length = struct.unpack("<I", mm[pos+2:pos+6])[0]

                if pos + 6 + length + 4 > len(mm):
                    pos += 1
                    continue

                payload = mm[pos+6:pos+6+length]
                checksum = struct.unpack("<I", mm[pos+6+length:pos+6+length+4])[0]

                expected_checksum = zlib.crc32(payload + salt) & 0xFFFFFFFF

                if checksum == expected_checksum:
                    try:
                        data = json.loads(payload.decode('utf-8'))
                        writer.writerow([data.get("file_id", ""), data.get("path", ""), data.get("symlink_target", "")])
                        pos += 6 + length + 4
                    except Exception:
                        pos += 1
                else:
                    pos += 1
            mm.close()
    except Exception as e:
        pass

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/oracle_parse_dump

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
