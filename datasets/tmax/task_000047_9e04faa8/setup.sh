#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/extracted

    python3 -c '
import struct

files = [
    ("data/sensor1.csv", b"timestamp,value\n1,10.5"),
    ("data/sensor2.csv", b"timestamp,value\n1,20.1"),
    ("../overwritten_secret.txt", b"hacked_data"),
    ("data/../../etc/shadow", b"fake_shadow_data"),
    ("notes.txt", b"experiment notes"),
    ("nested/dir/../safe.txt", b"safe content")
]

with open("/home/user/dataset.bin", "wb") as f:
    f.write(b"DATA")
    for path, content in files:
        path_bytes = path.encode("utf-8")
        f.write(struct.pack("<H", len(path_bytes)))
        f.write(path_bytes)
        f.write(struct.pack("<I", len(content)))
        f.write(content)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
