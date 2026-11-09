#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import struct

# Create dump.bin
with open('/home/user/dump.bin', 'wb') as f:
    # Valid chunk 1
    str1 = b'normal_string_123'
    f.write(b'CHNK' + struct.pack('<I', len(str1)) + str1)

    # Valid chunk 2
    str2 = b'debug_log_started'
    f.write(b'CHNK' + struct.pack('<I', len(str2)) + str2)

    # Corrupted chunk (size is extremely large)
    f.write(b'CHNK' + struct.pack('<I', 0xFFFFFFFF) + b'junk')

    # Valid chunk 3 - High Entropy String
    str3 = b'zQ8#kP9!mB4$vX1&'
    f.write(b'CHNK' + struct.pack('<I', len(str3)) + str3)

    # Truncated chunk at the end
    f.write(b'CHN')

# Create extractor.py
extractor_code = """import sys
import struct

def parse(filename):
    with open(filename, 'rb') as f:
        data = f.read()

    idx = 0
    candidates = []
    while idx < len(data):
        magic = data[idx:idx+4]
        if magic != b'CHNK':
            idx += 1
            continue

        # BUG: Doesn't check if idx+8 exceeds len(data), and doesn't check if size exceeds remaining data
        size = struct.unpack('<I', data[idx+4:idx+8])[0]

        chunk_data = data[idx+8 : idx+8+size]
        if chunk_data:
            candidates.append(chunk_data.decode('ascii', errors='ignore'))

        idx += 8 + size

    return candidates

if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(1)
    c = parse(sys.argv[1])
    with open('/home/user/candidates.txt', 'w') as f:
        for cand in c:
            f.write(cand + '\\n')
"""

with open('/home/user/extractor.py', 'w') as f:
    f.write(extractor_code)
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

chmod -R 777 /home/user
