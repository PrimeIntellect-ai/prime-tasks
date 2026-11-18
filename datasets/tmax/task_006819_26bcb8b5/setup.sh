#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pyyaml

    useradd -m -s /bin/bash user || true

    python3 -c '
import os
import json
import zipfile
import tarfile
import io
import time

os.makedirs("/home/user/backups", exist_ok=True)

# Create backup_01.zip
with zipfile.ZipFile("/home/user/backups/backup_01.zip", "w") as zf:
    zf.writestr("config.json", json.dumps({"version": 1, "settings": {"theme": "dark"}}))

# Create backup_02.tar.gz
with tarfile.open("/home/user/backups/backup_02.tar.gz", "w:gz") as tf:
    data = json.dumps({"version": 2, "settings": {"theme": "light", "plugins": ["auth"]}}).encode()
    ti = tarfile.TarInfo(name="config.json")
    ti.size = len(data)
    ti.mtime = int(time.time())
    tf.addfile(ti, io.BytesIO(data))

# Create corrupted backup_03.tar.gz
with open("/home/user/backups/backup_03.tar.gz", "wb") as f:
    f.write(b"\x1f\x8b\x08\x00\x00\x00\x00\x00\x00\x03randomgarbage")

# Create backup_04.zip
with zipfile.ZipFile("/home/user/backups/backup_04.zip", "w") as zf:
    zf.writestr("config.json", json.dumps({"version": 4, "settings": {"theme": "blue"}}))

# Create corrupted backup_05.zip
with open("/home/user/backups/backup_05.zip", "wb") as f:
    f.write(b"PK\x03\x04randomgarbagehere")
'

    chmod -R 777 /home/user
