#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backups
    mkdir -p /home/user/tmp/src

    python3 -c '
import tarfile
import os
import shutil

os.makedirs("/home/user/backups", exist_ok=True)
os.makedirs("/home/user/tmp/src", exist_ok=True)

# 1. Create base backup
with open("/home/user/tmp/README.md", "w") as f: f.write("Base v1")
with open("/home/user/tmp/src/app.py", "w") as f: f.write("print(\"Hello\")")
with tarfile.open("/home/user/backups/base.tar.gz", "w:gz") as tar:
    tar.add("/home/user/tmp/README.md", arcname="README.md")
    tar.add("/home/user/tmp/src/app.py", arcname="src/app.py")

# 2. Create inc1 backup
with open("/home/user/tmp/src/app.py", "w") as f: f.write("print(\"Hello v2\")")
with open("/home/user/tmp/src/utils.py", "w") as f: f.write("def foo(): pass")
with tarfile.open("/home/user/backups/inc1.tar.gz", "w:gz") as tar:
    tar.add("/home/user/tmp/src/app.py", arcname="src/app.py")
    tar.add("/home/user/tmp/src/utils.py", arcname="src/utils.py")

# 3. Create inc2 backup (with zip-slip payload)
with open("/home/user/tmp/docs.md", "w") as f: f.write("Docs")
with open("/home/user/tmp/malicious.txt", "w") as f: f.write("Owned")
with tarfile.open("/home/user/backups/inc2.tar.gz", "w:gz") as tar:
    tar.add("/home/user/tmp/docs.md", arcname="docs/index.md")
    # Malicious entry
    info = tarfile.TarInfo(name="../system_config.txt")
    with open("/home/user/tmp/malicious.txt", "rb") as f:
        info.size = os.path.getsize("/home/user/tmp/malicious.txt")
        tar.addfile(info, f)

# 4. Create backup.log
log_content = """=== Backup Record ===
ID: 3
Date: 2023-10-03
File: inc2.tar.gz
Type: Incremental
=====================
=== Backup Record ===
ID: 1
Date: 2023-10-01
File: base.tar.gz
Type: Full
=====================
=== Backup Record ===
ID: 2
Date: 2023-10-02
File: inc1.tar.gz
Type: Incremental
====================="""
with open("/home/user/backups/backup.log", "w") as f:
    f.write(log_content)

shutil.rmtree("/home/user/tmp")
'

    chmod -R 777 /home/user
