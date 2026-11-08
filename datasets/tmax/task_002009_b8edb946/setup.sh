#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc tesseract-ocr python3-pil
    pip3 install pytest

    mkdir -p /app

    # Create the oracle program
    cat << 'EOF' > /app/oracle_barc2tar
#!/usr/bin/env python3
import sys
import struct
import tarfile
import io

def main():
    try:
        magic = sys.stdin.buffer.read(4)
        if len(magic) < 4 or magic != b'BARC':
            sys.stderr.write("Invalid magic bytes\n")
            sys.exit(1)

        count_bytes = sys.stdin.buffer.read(4)
        if len(count_bytes) < 4:
            sys.stderr.write("Truncated header\n")
            sys.exit(1)
        count = struct.unpack('<I', count_bytes)[0]

        with tarfile.open(fileobj=sys.stdout.buffer, mode='w|', format=tarfile.GNU_FORMAT) as tar:
            for _ in range(count):
                name_bytes = sys.stdin.buffer.read(32)
                if len(name_bytes) < 32:
                    sys.stderr.write("Truncated entry header\n")
                    sys.exit(1)

                try:
                    name = name_bytes.split(b'\x00', 1)[0].decode('ascii')
                except UnicodeDecodeError:
                    sys.stderr.write("Non-ASCII filename\n")
                    sys.exit(1)

                size_bytes = sys.stdin.buffer.read(8)
                if len(size_bytes) < 8:
                    sys.stderr.write("Truncated entry size\n")
                    sys.exit(1)
                size = struct.unpack('<Q', size_bytes)[0]

                data = sys.stdin.buffer.read(size)
                if len(data) < size:
                    sys.stderr.write("Truncated file data\n")
                    sys.exit(1)

                tarinfo = tarfile.TarInfo(name=name)
                tarinfo.size = size
                tar.addfile(tarinfo, io.BytesIO(data))
    except Exception as e:
        sys.stderr.write(str(e) + "\n")
        sys.exit(1)

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/oracle_barc2tar

    # Create the image specification
    cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw
text = """FORMAT SPECIFICATION - BARC v1
Magic Bytes: BARC (0x42 0x41 0x52 0x43)
Endianness: Little Endian
Header:
- 4 bytes: Magic bytes
- 4 bytes (u32): Count of files in archive
Entries (repeated Count times):
- 32 bytes: Filename (ASCII, null-padded at the end)
- 8 bytes (u64): File size in bytes (N)
- N bytes: File data payload"""
img = Image.new('RGB', (800, 400), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), text, fill=(0,0,0))
img.save('/app/archive_spec.png')
EOF
    python3 /tmp/make_image.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
