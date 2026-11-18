#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import zipfile
import random

os.makedirs("/home/user", exist_ok=True)
os.makedirs("/home/user/extracted", exist_ok=True)
os.makedirs("/home/user/gcode_chunks", exist_ok=True)

# Generate synthetic GCode
gcode1 = "; Header\nG1 X10 Y10\n;comment\nG1 Z5\n" * 600  # 1200 lines clean
gcode2 = "M104 S200\n; Set temp\nG28\n" * 150 # 300 lines clean
# Generate synthetic WAL (binary)
wal1 = os.urandom(1024)
wal2 = os.urandom(2048)
wal3 = os.urandom(512)

# Create the zip file with zip slip vulnerability
zip_path = "/home/user/dataset.zip"
with zipfile.ZipFile(zip_path, 'w') as zf:
    # Normal files
    zf.writestr("scaffold1.gcode", gcode1)
    zf.writestr("scaffold2.gcode", gcode2)
    zf.writestr("sensor_a.wal", wal1)
    zf.writestr("sensor_b.wal", wal2)
    zf.writestr("sensor_c.wal", wal3)

    # Malicious files (Zip Slip)
    zf.writestr("../etc/passwd_overwrite", "malicious_content")
    zf.writestr("data/../../home/user/.bashrc_override", "alias ls='rm -rf'")
    zf.writestr("/absolute/path/test.txt", "bad")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
