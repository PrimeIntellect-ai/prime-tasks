#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip unzip tar gawk sed
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import tarfile
import zipfile
import io

dirs = [
    "/home/user/incoming_artifacts",
    "/home/user/safe_artifacts",
    "/home/user/quarantine",
    "/home/user/processed"
]
for d in dirs:
    os.makedirs(d, exist_ok=True)

# 1. Safe Tar
with tarfile.open("/home/user/incoming_artifacts/safe_app.tar.gz", "w:gz") as t:
    ti = tarfile.TarInfo("bin/run.sh")
    data = b"echo hello"
    ti.size = len(data)
    t.addfile(ti, fileobj=io.BytesIO(data))

# 2. Safe Zip
with zipfile.ZipFile("/home/user/incoming_artifacts/safe_data.zip", "w") as z:
    z.writestr("data/info.txt", "hello world")

# 3. Malicious Tar (Directory Traversal)
with tarfile.open("/home/user/incoming_artifacts/slip_tar.tar.gz", "w:gz") as t:
    ti1 = tarfile.TarInfo("normal.txt")
    ti1.size = 0
    t.addfile(ti1, fileobj=io.BytesIO(b""))
    ti2 = tarfile.TarInfo("../evil.sh")
    ti2.size = 0
    t.addfile(ti2, fileobj=io.BytesIO(b""))

# 4. Malicious Zip (Absolute Path)
with zipfile.ZipFile("/home/user/incoming_artifacts/slip_zip.zip", "w") as z:
    z.writestr("good.txt", "ok")
    z.writestr("/etc/shadow", "fake")

# 5. Corrupt Tar
with open("/home/user/incoming_artifacts/bad_archive.tar.gz", "wb") as f:
    f.write(b"Not a tar file at all. Just some garbage bytes.")

# 6. Corrupt Zip
with zipfile.ZipFile("/home/user/incoming_artifacts/broken_data.zip", "w") as z:
    z.writestr("file.txt", "will be corrupted")
with open("/home/user/incoming_artifacts/broken_data.zip", "r+b") as f:
    f.seek(0)
    f.write(b"BADHEADER000")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
