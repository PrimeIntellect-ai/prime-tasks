#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest hypothesis

    mkdir -p /home/user/project

    cat << 'EOF' > /home/user/project/utils.py
def encode_entry(s: str, enc_type: int) -> bytes:
    if enc_type == 1:
        b = s.encode('utf-8')
    elif enc_type == 2:
        b = s.encode('utf-16le')
    else:
        raise ValueError("Invalid enc_type")

    length = len(b)
    return bytes([enc_type]) + length.to_bytes(2, 'little') + b
EOF

    cat << 'EOF' > /home/user/project/organizer.py
import sys

def decode_entry(data: bytes, offset: int):
    # BUG: Assumes UTF-8, ignores encoding byte
    enc_type = data[offset]
    length = int.from_bytes(data[offset+1:offset+3], 'little')
    start = offset + 3
    end = start + length

    # Buggy fixed decoding:
    val = data[start:end].decode('utf-8')
    return val, end

def read_index(filepath: str):
    with open(filepath, 'rb') as f:
        data = f.read()

    offset = 0
    results = []
    while offset < len(data):
        val, offset = decode_entry(data, offset)
        results.append(val)
    return results

def main():
    if len(sys.argv) < 2:
        return

    filepath = sys.argv[1]
    paths = read_index(filepath)
    paths.sort()

    with open('/home/user/organized_files.txt', 'w') as f:
        for p in paths:
            f.write(p + '\n')

if __name__ == '__main__':
    main()
EOF

    python3 -c "
import sys
sys.path.append('/home/user/project')
from utils import encode_entry
files = ['lib/libmath.so', 'src/main.cpp', 'CMakeLists.txt', 'build/config.h', 'include/utils.hpp', 'lib/libUTF16_test.so']
encodings = [1, 1, 1, 2, 1, 2]

with open('/home/user/project/index.bin', 'wb') as f:
    for path, enc in zip(files, encodings):
        f.write(encode_entry(path, enc))
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
