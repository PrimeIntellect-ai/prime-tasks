#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import os
import struct

os.makedirs("/home/user/datasets/group_A/nested", exist_ok=True)
os.makedirs("/home/user/datasets/group_B", exist_ok=True)

with open("/home/user/dataset.conf", "w") as f:
    f.write("RSCH\nDATA\n")

def make_file(path, magic, payload):
    with open(path, "wb") as f:
        f.write(magic.encode('ascii'))
        f.write(struct.pack("<I", len(payload)))
        f.write(payload)

# Valid files
make_file("/home/user/datasets/group_A/sample1.dat", "RSCH", b"PAYLOAD_A1_00000")
make_file("/home/user/datasets/group_A/nested/sample2.dat", "DATA", b"HELO_WORLD")
make_file("/home/user/datasets/group_B/data.dat", "RSCH", b"TESTING_DATA_123")

# Invalid files (wrong magic, wrong extension)
make_file("/home/user/datasets/group_B/junk.dat", "JUNK", b"IGNORE_ME")
make_file("/home/user/datasets/group_B/not_dat.txt", "RSCH", b"SHOULD_BE_IGNORED")
with open("/home/user/datasets/group_A/empty.dat", "wb") as f:
    f.write(b"RSC") # Too short
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

chmod -R 777 /home/user
