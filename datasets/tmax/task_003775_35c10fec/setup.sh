#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import zipfile
import tarfile

base_dir = "/home/user"
uploads_dir = os.path.join(base_dir, "uploads")
processed_dir = os.path.join(base_dir, "processed")

os.makedirs(uploads_dir, exist_ok=True)
os.makedirs(processed_dir, exist_ok=True)

# 1. Safe Zip: safe_data.zip
safe_zip_path = os.path.join(uploads_dir, "safe_data.zip")
with zipfile.ZipFile(safe_zip_path, 'w') as zf:
    zf.writestr("notes.txt", "München".encode("cp1252"))
    zf.writestr("data/stats.bin", b'\x00\x01\x02\x03')

# 2. Malicious Tar: bad_actor.tar.gz
bad_tar_path = os.path.join(uploads_dir, "bad_actor.tar.gz")
with tarfile.open(bad_tar_path, "w:gz") as tf:
    info = tarfile.TarInfo(name="../../home/user/escaped.txt")
    info.size = 4
    with open("/tmp/dummy.bin", "wb") as f:
        f.write(b"1234")
    tf.add("/tmp/dummy.bin", arcname=info.name)

# 3. Malicious Zip: mixed.zip
mixed_zip_path = os.path.join(uploads_dir, "mixed.zip")
with zipfile.ZipFile(mixed_zip_path, 'w') as zf:
    zf.writestr("good.bin", b'\xaa\xbb')
    zf.writestr("dir/../../etc/passwd", b"fake passwd data")

# 4. Safe Tar: safe_archive.tar.gz
safe_tar_path = os.path.join(uploads_dir, "safe_archive.tar.gz")
with tarfile.open(safe_tar_path, "w:gz") as tf:
    with open("/tmp/voila.txt", "wb") as f:
        f.write("Voilà".encode("cp1252"))
    tf.add("/tmp/voila.txt", arcname="docs/report.txt")
EOF

    python3 /tmp/setup.py

    chmod -R 777 /home/user
