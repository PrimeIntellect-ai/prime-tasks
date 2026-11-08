#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/investigation

    # Create memdump.bin
    python3 -c "
import os
with open('/home/user/investigation/memdump.bin', 'wb') as f:
    f.write(os.urandom(1024))
    f.write(b'C2CFG{0052}YjY0OmFIUjBjSE02THk5M2QzY3VZMkZ0Y0d4bExtTnZiUT09')
    f.write(os.urandom(1024))
"

    # Create extractor.py
    cat << 'EOF' > /home/user/investigation/extractor.py
import re
import base64

def parse_config_block(data: bytes):
    # Bug: crashes on non-ascii
    text = data.decode('ascii')
    match = re.search(r'C2CFG\{(\d{4})\}(.*)', text)
    if not match:
        return None
    length = int(match.group(1))
    if length > 9000:
        raise ValueError("Corrupt Header")
    payload = match.group(2)[:length]
    return payload

def decode_c2(payload):
    current = payload
    while True:
        if current.startswith('b64:'):
            current = current[4:]

        # Bug: incorrect padding handling causes infinite loop
        if len(current) % 4 != 0:
            current += '=' * (4 - len(current) % 4)

        try:
            decoded = base64.b64decode(current).decode('utf-8')
        except Exception:
            break

        if decoded == current:
            break

        current = decoded

        # simulated infinite loop trigger if padding is stripped by mistake
        if current.endswith('=='):
            current = current[:-2]

    return current

if __name__ == '__main__':
    with open('memdump.bin', 'rb') as f:
        data = f.read()
    try:
        payload = parse_config_block(data)
        if payload:
            print(decode_c2(payload))
    except Exception as e:
        print("Error:", e)
EOF

    # Create fuzz_corpus.txt
    cat << 'EOF' > /home/user/investigation/fuzz_corpus.txt
C2CFG{0010}dummy
C2CFG{9001}crashme
C2CFG{0020}safedata
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
