#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip unzip tar gzip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import os
import json
import tarfile
import zipfile
import shutil

os.makedirs("/home/user/setup_tmp", exist_ok=True)
os.chdir("/home/user/setup_tmp")

# Create log 1
log1 = [
    {"timestamp": "2023-01-01T12:00:00Z", "level": "INFO", "message": "System booted successfully."},
    {"timestamp": "2023-01-01T12:01:00Z", "level": "DEBUG", "message": "Loading modules..."},
    {"timestamp": "2023-01-01T12:05:00Z", "level": "ERROR", "message": "Timeout    occured!!!"}
]
with open("log1.jsonl", "w") as f:
    for entry in log1:
        f.write(json.dumps(entry) + "\n")

# Create log 2
log2 = [
    {"timestamp": "2023-01-01T11:59:00Z", "level": "DEBUG", "message": "Pre-boot sequence initiated."},
    {"timestamp": "2023-01-01T12:10:00Z", "level": "WARN", "message": "Disk space loooow"},
    {"timestamp": "2023-01-01T12:15:00Z", "level": "INFO", "message": "All good now."}
]
with open("log2.jsonl", "w") as f:
    for entry in log2:
        f.write(json.dumps(entry) + "\n")

# Pack log1 into a zip
with zipfile.ZipFile("chunk1.zip", "w") as z:
    z.write("log1.jsonl")

# Pack log2 into a tar.gz
with tarfile.open("chunk2.tar.gz", "w:gz") as t:
    t.add("log2.jsonl")

# Pack both chunks into legacy_logs.tar
os.chdir("/home/user")
with tarfile.open("legacy_logs.tar", "w") as t:
    t.add("setup_tmp/chunk1.zip", arcname="chunk1.zip")
    t.add("setup_tmp/chunk2.tar.gz", arcname="chunk2.tar.gz")

# Cleanup setup tmp
shutil.rmtree("/home/user/setup_tmp")
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

chmod -R 777 /home/user
