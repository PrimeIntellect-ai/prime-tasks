#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_archives.py
import os
import zipfile
import tarfile

base_dir = "/home/user"
incoming_dir = os.path.join(base_dir, "incoming_artifacts")
os.makedirs(incoming_dir, exist_ok=True)
os.makedirs(os.path.join(base_dir, "curated_artifacts"), exist_ok=True)
os.makedirs(os.path.join(base_dir, "quarantine"), exist_ok=True)

# 1. Safe ZIP
safe_zip = os.path.join(incoming_dir, "safe_app.zip")
with zipfile.ZipFile(safe_zip, 'w') as zf:
    zf.writestr("app/main.py", "print('hello')")
    zf.writestr("app/data.bin", b"\x00\x01\x02")

# 2. Malicious ZIP (Zip Slip)
mal_zip = os.path.join(incoming_dir, "malicious_payload.zip")
with zipfile.ZipFile(mal_zip, 'w') as zf:
    zf.writestr("../../../etc/shadow_overwrite", "hacked")
    zf.writestr("normal_file.txt", "normal")

# 3. Safe TAR.GZ
safe_tar = os.path.join(incoming_dir, "safe_lib.tar.gz")
with tarfile.open(safe_tar, 'w:gz') as tf:
    info = tarfile.TarInfo(name="lib/util.py")
    data = b"def foo(): pass"
    info.size = len(data)
    with open("/tmp/temp_tar_data", "wb") as temp:
        temp.write(data)
    with open("/tmp/temp_tar_data", "rb") as temp:
        tf.addfile(info, temp)

# 4. Malicious TAR.GZ
mal_tar = os.path.join(incoming_dir, "sneaky_lib.tar.gz")
with tarfile.open(mal_tar, 'w:gz') as tf:
    info = tarfile.TarInfo(name="../../home/user/.ssh/authorized_keys")
    data2 = b"ssh-rsa AAAA..."
    info.size = len(data2)
    with open("/tmp/temp_tar_data2", "wb") as temp:
        temp.write(data2)
    with open("/tmp/temp_tar_data2", "rb") as temp:
        tf.addfile(info, temp)

# 5. Corrupted ZIP
corrupt_zip = os.path.join(incoming_dir, "broken_data.zip")
with open(corrupt_zip, 'wb') as f:
    f.write(b"PK\x03\x04This is not a valid zip file and is corrupted...")
EOF

    python3 /tmp/setup_archives.py
    rm -f /tmp/setup_archives.py /tmp/temp_tar_data /tmp/temp_tar_data2

    chmod -R 777 /home/user
