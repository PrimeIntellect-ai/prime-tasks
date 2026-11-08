#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest Pillow

mkdir -p /app

cat << 'EOF' > /app/make_image.py
from PIL import Image, ImageDraw
text = """DSAR Format v1
All multi-byte integers are Little Endian.

Header:
[0-3] Magic 'DSAR'
[4-5] Number of records (uint16)

For each record (sequential after header):
[0] Path length L (uint8)
[1 to L] File path (ascii string)
[L+1 to L+8] File offset (uint64)
[L+9 to L+16] File size (uint64)
[L+17 to L+20] CRC32 of file data (uint32)

Security constraint: Reject paths containing '../' or starting with '/'.
"""
img = Image.new('RGB', (800, 600), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), text, fill=(0,0,0))
img.save('/app/format_spec.png')
EOF

python3 /app/make_image.py
rm /app/make_image.py

cat << 'EOF' > /app/oracle_parser
#!/usr/bin/env python3
import struct
import sys
import mmap
import os

def main():
    if len(sys.argv) != 2:
        sys.exit(1)

    file_path = sys.argv[1]
    with open(file_path, "rb") as f:
        f.seek(0, 2)
        if f.tell() < 6:
            return
        f.seek(0)

        with mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as mm:
            magic = mm[0:4]
            if magic != b'DSAR':
                return

            num_records = struct.unpack("<H", mm[4:6])[0]
            cursor = 6

            for _ in range(num_records):
                if cursor >= len(mm): break
                path_len = mm[cursor]
                cursor += 1

                if cursor + path_len + 20 > len(mm): break

                path_bytes = mm[cursor:cursor+path_len]
                path = path_bytes.decode('ascii', errors='replace')
                cursor += path_len

                offset, size, crc = struct.unpack("<QQI", mm[cursor:cursor+20])
                cursor += 20

                if path.startswith('/') or '../' in path:
                    continue

                print(f"Valid: {path} | Offset: {offset} | Size: {size}")

if __name__ == '__main__':
    main()
EOF
chmod +x /app/oracle_parser

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
