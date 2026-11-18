#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import os
import struct

os.makedirs('/home/user/incoming_data', exist_ok=True)
os.makedirs('/home/user/organized_data', exist_ok=True)

def write_dat(filename, magic, class_id, payload, make_ready=True):
    path = f'/home/user/incoming_data/{filename}.dat'
    with open(path, 'wb') as f:
        f.write(struct.pack('<IHH', magic, class_id, len(payload)))
        f.write(payload)
    if make_ready:
        open(f'/home/user/incoming_data/{filename}.ready', 'w').close()

# File 1: Valid, Class 1
write_dat('chunk_a', 0xDEADBEEF, 1, b'A'*5 + b'B'*5, True)
# File 2: No ready file, should be ignored
write_dat('chunk_b', 0xDEADBEEF, 2, b'C'*10, False)
# File 3: Invalid magic, should be ignored
write_dat('chunk_c', 0xBAADF00D, 1, b'D'*10, True)
# File 4: Valid, Class 5, large payload to test 255 limit
write_dat('chunk_d', 0xDEADBEEF, 5, b'X'*300 + b'Y'*2, True)

EOF

python3 /tmp/setup.py

chmod -R 777 /home/user
