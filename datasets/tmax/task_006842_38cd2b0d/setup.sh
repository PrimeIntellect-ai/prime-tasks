#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/parts

    cat << 'EOF' > /tmp/setup.py
import os
import tarfile
import io
import subprocess

os.makedirs("/home/user/parts", exist_ok=True)
os.chdir("/home/user")

# Create the malicious tarfile
tar_path = "/home/user/complete_backup_temp.tar.gz"
with tarfile.open(tar_path, "w:gz") as tar:
    # Safe 1
    info = tarfile.TarInfo("logs/system.log")
    info.size = 12
    tar.addfile(info, io.BytesIO(b"system is ok"))

    # Safe 2
    info = tarfile.TarInfo("logs/auth.log")
    info.size = 9
    tar.addfile(info, io.BytesIO(b"auth fail"))

    # Malicious 1 (Absolute)
    info = tarfile.TarInfo("/etc/shadow_backup")
    info.size = 6
    tar.addfile(info, io.BytesIO(b"hacked"))

    # Malicious 2 (Relative escape)
    info = tarfile.TarInfo("../../../root/secret.txt")
    info.size = 6
    tar.addfile(info, io.BytesIO(b"hacked"))

# Split the tarfile
subprocess.run(["split", "-b", "100", tar_path, "/home/user/parts/backup_part_"])
os.remove(tar_path)

# Generate broken manifest
parts = sorted(os.listdir("/home/user/parts"))
manifest_content = '<?xml version="1.0"?>\n<backup>\n  <parts>\n'
for i, part in enumerate(parts):
    manifest_content += f'    [part id="{i+1}"]{part}</prt>\n'
manifest_content += '  </parts>\n</backup>\n'

with open("/home/user/manifest.xml.broken", "w") as f:
    f.write(manifest_content)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
