#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user/backup
    mkdir -p /home/user/extracted

    # Generate the binary archive
    python3 -c '
import struct

files = {
    "config.json": b"{\"key\": \"value\"}",
    "src/main.py": b"print(\"hello\")",
    "assets/logo.png": b"PNG..."
}

with open("/app/project_archive.bin", "wb") as f:
    f.write(b"PROJ\x01\x00")
    for path, data in files.items():
        path_bytes = path.encode("ascii")
        f.write(struct.pack("<H", len(path_bytes)))
        f.write(path_bytes)
        f.write(struct.pack("<I", len(data)))
        f.write(data)
'

    # Generate the voice memo
    espeak -w /app/voice_memo_001.wav "The secret project code is DELTA forty two"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
