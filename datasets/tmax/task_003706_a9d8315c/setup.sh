#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
import os
import zipfile
import tarfile
import io

base_dir = "/home/user/uploaded_archives"
os.makedirs(f"{base_dir}/project_a", exist_ok=True)
os.makedirs(f"{base_dir}/project_b/nested", exist_ok=True)

# 1. Clean zip
with zipfile.ZipFile(f"{base_dir}/project_a/clean1.zip", "w") as z:
    z.writestr("file1.txt", "data")
    z.writestr("dir/file2.txt", "data")

# 2. Malicious zip
with zipfile.ZipFile(f"{base_dir}/project_a/malicious1.zip", "w") as z:
    z.writestr("file1.txt", "data")
    z.writestr("../../etc/shadow", "fake shadow data")

# 3. Clean tar
with tarfile.open(f"{base_dir}/project_b/clean2.tar", "w") as t:
    ti = tarfile.TarInfo("safe.txt")
    ti.size = 4
    t.addfile(ti, io.BytesIO(b"data"))

# 4. Malicious tar
with tarfile.open(f"{base_dir}/project_b/nested/malicious2.tar", "w") as t:
    ti = tarfile.TarInfo("/var/log/syslog")
    ti.size = 4
    t.addfile(ti, io.BytesIO(b"data"))
'

    chmod -R 777 /home/user
