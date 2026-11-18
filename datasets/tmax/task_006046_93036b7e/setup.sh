#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/artifacts

    python3 -c '
import struct
import os

records = [
    (b"docs/readme.txt", 100, 500),
    (b"bin/../../etc/passwd", 600, 1024),
    (b"scripts/install.sh", 1624, 200),
    (b"../config/system.yml", 1824, 150),
    (b"safe/../path/file", 1974, 10)
]

with open("/home/user/artifacts/index.bin", "wb") as f:
    f.write(b"ARTIFACT_v1\0")
    for name, offset, size in records:
        f.write(struct.pack("<H", len(name)))
        f.write(name)
        f.write(struct.pack("<II", offset, size))
'

    chmod -R 777 /home/user
