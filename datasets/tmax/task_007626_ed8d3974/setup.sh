#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import tarfile
import shutil

base_dir = "/home/user"
tmp_dir = os.path.join(base_dir, "setup_tmp")
os.makedirs(tmp_dir, exist_ok=True)
os.chdir(tmp_dir)

# 1. ISO-8859-1 Text file
with open("readme.txt", "wb") as f:
    f.write("Legacy System v1.0\nFeatures: \xFCber fast execution.\n".encode("iso-8859-1"))

# 2. Binary files with spaces
with open("core system app.bin", "wb") as f:
    f.write(b"\x7fELF...core")

with open("diagnostic tool.bin", "wb") as f:
    f.write(b"\x7fELF...diag")

# 3. Malicious Symlink (Zip Slip equivalent)
os.symlink("/etc/passwd", "system_passwords")

# 4. Valid Symlink (Should be kept)
os.symlink("readme.txt", "info.txt")

tar_path = os.path.join(base_dir, "artifacts.tar")
with tarfile.open(tar_path, "w") as tar:
    tar.add("readme.txt")
    tar.add("core system app.bin")
    tar.add("diagnostic tool.bin")
    tar.add("system_passwords")
    tar.add("info.txt")

os.chdir(base_dir)
shutil.rmtree(tmp_dir)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chown -R user:user /home/user
    chmod -R 777 /home/user
