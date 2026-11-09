#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip zip unzip tar gzip coreutils
pip3 install pytest

mkdir -p /home/user/backups
mkdir -p /home/user/setup_temp
cd /home/user/setup_temp

cat << 'EOF' > setup.py
import os
import subprocess
import zipfile

log1 = "[2023-10-01 12:00:00] ERROR Disk full\n[2023-10-01 12:05:00] INFO Cleanup started\n"
log2 = "[2023-10-01 12:10:00] WARN High memory usage\nInvalid log line here\n[2023-10-01 12:15:00] INFO Process killed\n"

os.makedirs("valid1", exist_ok=True)
with open("valid1/app.log", "w") as f: f.write(log1)
subprocess.run(["tar", "-czf", "valid1.tar.gz", "-C", "valid1", "app.log"])

os.makedirs("valid2", exist_ok=True)
with open("valid2/system.log", "w") as f: f.write(log2)
subprocess.run(["tar", "-czf", "valid2.tar.gz", "-C", "valid2", "system.log"])

with open("corrupt.tar.gz", "wb") as f:
    f.write(b"this is not a valid gzip or tar archive at all, just garbage bytes.")

subprocess.run(["tar", "-cf", "nested.tar", "valid1.tar.gz", "valid2.tar.gz", "corrupt.tar.gz"])

with zipfile.ZipFile("archive.zip", "w", zipfile.ZIP_DEFLATED) as zf:
    zf.write("nested.tar")

with open("archive.zip", "rb") as f:
    data = f.read()

half = len(data) // 2
with open("/home/user/backups/archive.zip.001", "wb") as f:
    f.write(data[:half])
with open("/home/user/backups/archive.zip.002", "wb") as f:
    f.write(data[half:])
EOF

python3 setup.py
cd /
rm -rf /home/user/setup_temp

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
