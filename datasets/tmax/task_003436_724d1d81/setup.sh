#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest pytesseract Pillow

    mkdir -p /app
    mkdir -p /opt/oracle

    # Generate the whiteboard image
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 600), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = '''Backup WAL Format (v1)
----------------------
Header:
  4 bytes MAGIC: b\'BKP1\'

Records (repeats until EOF):
  1 byte OP_CODE:
     0x01 = CREATE
     0x02 = UPDATE
     0x03 = DELETE
  2 bytes PATH_LEN (unsigned short, big-endian)
  [PATH_LEN] bytes PATH (utf-8 string)
  4 bytes CHECKSUM (unsigned int, big-endian)'''
d.text((10,10), text, fill=(0,0,0))
img.save('/app/whiteboard.png')
"

    # Create the oracle script
    cat << 'EOF' > /opt/oracle/reference_parser.py
import sys
import struct
import fcntl

def parse_wal(filepath):
    state = {}
    with open(filepath, 'rb') as f:
        fcntl.flock(f, fcntl.LOCK_SH)
        try:
            magic = f.read(4)
            if magic != b'BKP1':
                return
            while True:
                op_byte = f.read(1)
                if not op_byte:
                    break
                op = op_byte[0]

                path_len_data = f.read(2)
                if len(path_len_data) < 2:
                    break
                path_len = struct.unpack('>H', path_len_data)[0]

                path = f.read(path_len).decode('utf-8')

                checksum_data = f.read(4)
                if len(checksum_data) < 4:
                    break
                checksum = struct.unpack('>I', checksum_data)[0]

                if op == 0x01 or op == 0x02:
                    state[path] = checksum
                elif op == 0x03:
                    if path in state:
                        del state[path]
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)

    for path in sorted(state.keys()):
        print(f"{path} : {state[path]:08x}")

if __name__ == '__main__':
    parse_wal(sys.argv[1])
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
