#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import struct
import os

os.makedirs("/home/user", exist_ok=True)

files = [
    ("normal1.gcode", b"G1 X10 Y10 E2.5\nG1 X20 E1.5\nM104 S200\n"),
    ("../malicious_script.sh", b"echo 'hacked'"),
    ("/etc/fake_shadow", b"root::18704:0:99999:7:::"),
    ("nested/dir/safe.gcode", b"G28\nG1 Z1.0 E0.5\nG1 X0 Y0 E0.25\n"),
    ("metadata.txt", b"Experiment 42 - Standard PLA"),
]

with open("/home/user/dataset.bak", "wb") as f:
    f.write(b"DATASET\0")
    for path, content in files:
        path_bytes = path.encode('utf-8')
        f.write(struct.pack("<H", len(path_bytes)))
        f.write(path_bytes)
        f.write(struct.pack("<I", len(content)))
        f.write(content)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
