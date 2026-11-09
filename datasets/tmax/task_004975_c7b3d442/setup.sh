#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip binutils
pip3 install pytest pyinstaller

cat << 'EOF' > /tmp/oracle.py
import sys

def encode(data: bytes) -> bytes:
    if not data:
        return b"DOCX" + (0).to_bytes(4, 'little') + b'\x00'

    length = len(data)
    checksum = sum(data) % 256

    rle = bytearray()
    i = 0
    while i < length:
        count = 1
        while i + count < length and data[i + count] == data[i] and count < 255:
            count += 1
        rle.append(count)
        rle.append(data[i])
        i += count

    payload = bytearray(b ^ checksum for b in rle)
    return b"DOCX" + length.to_bytes(4, 'little') + bytes([checksum]) + payload

if __name__ == "__main__":
    data = sys.stdin.buffer.read()
    sys.stdout.buffer.write(encode(data))
EOF

pyinstaller --onefile /tmp/oracle.py
mkdir -p /app
cp dist/oracle /app/doc_encoder
strip /app/doc_encoder

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
