#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import json
import zipfile
import tarfile
import random

base_dir = "/home/user/backup_vault"
os.makedirs(os.path.join(base_dir, "db"), exist_ok=True)
os.makedirs(os.path.join(base_dir, "logs/2022"), exist_ok=True)

def make_valid_zip(path, archive_id):
    with zipfile.ZipFile(path, 'w') as zf:
        zf.writestr('metadata.json', json.dumps({"archive_id": archive_id}))
        zf.writestr('data.txt', "db backup data")

def make_valid_tar(path, archive_id):
    with tarfile.open(path, 'w:gz') as tf:
        metadata_content = json.dumps({"archive_id": archive_id}).encode('utf-8')
        with open("/tmp/metadata.json", "wb") as f:
            f.write(metadata_content)
        tf.add("/tmp/metadata.json", arcname="metadata.json")

def make_corrupt(path):
    with open(path, 'wb') as f:
        f.write(os.urandom(1024))

make_valid_zip(os.path.join(base_dir, "db/backup1.zip"), "DB-1001")
make_corrupt(os.path.join(base_dir, "db/backup2.zip"))
make_valid_tar(os.path.join(base_dir, "logs/2022/syslog.tar.gz"), "LOG-8888")
make_corrupt(os.path.join(base_dir, "logs/2022/authlog.tar.gz"))
EOF

    python3 /tmp/setup.py
    rm -f /tmp/setup.py /tmp/metadata.json

    chmod -R 777 /home/user
