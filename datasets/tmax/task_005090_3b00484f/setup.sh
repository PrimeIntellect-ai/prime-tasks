#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget tar
    pip3 install pytest fastapi uvicorn pydantic requests

    mkdir -p /app
    cd /app
    wget https://pypi.python.org/packages/source/t/tinydb/tinydb-4.7.0.tar.gz
    tar -xzf tinydb-4.7.0.tar.gz
    mv tinydb-4.7.0 tinydb
    rm tinydb-4.7.0.tar.gz

    cat << 'EOF' > patch_tinydb.py
import os

path = "/app/tinydb/tinydb/storages.py"
with open(path, "r") as f:
    lines = f.readlines()

new_lines = ["import threading\n"]
for line in lines:
    new_lines.append(line)
    if "def __init__(self, path: str" in line:
        new_lines.append("        self._lock = threading.Lock()\n")
    if "def write(self, data" in line:
        new_lines.append("        self._lock.acquire()\n")

with open(path, "w") as f:
    f.writelines(new_lines)
EOF

    python3 patch_tinydb.py
    rm patch_tinydb.py

    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
