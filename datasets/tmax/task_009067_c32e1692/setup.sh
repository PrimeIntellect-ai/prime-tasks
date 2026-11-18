#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy_docs
    mkdir -p /home/user/docs_out

    python3 -c '
import struct
import base64
import os

files = [
    ("doc1.bin", "intro.md", "# Welcome to the docs"),
    ("doc2.bin", "api/auth.md", "## Authentication API"),
    ("doc3.bin", "setup/install.md", "## Installation Instructions"),
    ("doc4.bin", "api/users/list.md", "## List Users API"),
]

for filename, path, text in files:
    with open(f"/home/user/legacy_docs/{filename}", "wb") as f:
        f.write(b"DOCB")
        f.write(struct.pack("<I", len(path)))
        f.write(path.encode("ascii"))
        f.write(base64.b64encode(text.encode("utf-8")))
'

    chmod -R 777 /home/user
