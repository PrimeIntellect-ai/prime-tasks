#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/parser.py
import sys
import struct

def parse_file(filepath):
    with open(filepath, 'rb') as f:
        data = f.read()

    if not data.startswith(b'MALW'):
        return

    idx = 4
    if idx + 2 > len(data):
        return

    num_chunks = struct.unpack('<H', data[idx:idx+2])[0]
    idx += 2

    for _ in range(num_chunks):
        if idx >= len(data):
            break
        ctype = data[idx]
        idx += 1

        if idx + 2 > len(data):
            break
        clen = struct.unpack('<H', data[idx:idx+2])[0]
        idx += 2

        if ctype == 0x42:
            if idx + 4 > len(data):
                break
            offset = struct.unpack('<I', data[idx:idx+4])[0]
            # Vulnerability: tries to unpack 8 bytes from an arbitrary offset that might be out of bounds
            val = struct.unpack('<d', data[offset:offset+8])[0]
            print(f"Extracted double: {val}")
            idx += 4
        else:
            idx += clen

if __name__ == '__main__':
    if len(sys.argv) > 1:
        parse_file(sys.argv[1])
EOF

python3 -c "
import struct
# 50 normal chunks, 1 malicious, 10 normal
out = b'MALW'
out += struct.pack('<H', 61)
for i in range(50):
    out += b'\x01' + struct.pack('<H', 4) + b'AAAA'
# Malicious chunk (type 0x42)
out += b'\x42' + struct.pack('<H', 4) + struct.pack('<I', 999999)
# Padding chunks
for i in range(10):
    out += b'\x01' + struct.pack('<H', 4) + b'BBBB'

with open('/home/user/suspicious.bin', 'wb') as f:
    f.write(out)
"

chmod -R 777 /home/user
