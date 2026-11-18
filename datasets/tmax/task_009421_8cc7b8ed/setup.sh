#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os

base_dir = "/home/user/raw_dataset"
os.makedirs(os.path.join(base_dir, "subject1"), exist_ok=True)
os.makedirs(os.path.join(base_dir, "subject2/sessionA"), exist_ok=True)
os.makedirs(os.path.join(base_dir, "subject2/sessionB"), exist_ok=True)
os.makedirs(os.path.join(base_dir, "subject3"), exist_ok=True)

# Valid file 1
with open(os.path.join(base_dir, "scan_root.dat"), "wb") as f:
    f.write(b"BRAN" + b"\x00" * 16) # 20 bytes

# Valid file 2
with open(os.path.join(base_dir, "subject1/scan1.dat"), "wb") as f:
    f.write(b"BRAN" + b"\x01\x02\x03\x04") # 8 bytes

# Invalid file 1 (corrupt header)
with open(os.path.join(base_dir, "subject1/corrupt.dat"), "wb") as f:
    f.write(b"ERR!" + b"\x00" * 12) # 16 bytes

# Valid file 3
with open(os.path.join(base_dir, "subject2/sessionA/scanA.dat"), "wb") as f:
    f.write(b"BRAN" + b"\xFF" * 10) # 14 bytes

# Invalid file 2 (too short)
with open(os.path.join(base_dir, "subject2/sessionB/short.dat"), "wb") as f:
    f.write(b"BR") # 2 bytes

# Valid file 4
with open(os.path.join(base_dir, "subject3/scan3.dat"), "wb") as f:
    f.write(b"BRAN" + b"\x0A" * 100) # 104 bytes
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
