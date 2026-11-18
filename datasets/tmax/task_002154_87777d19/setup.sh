#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Generate files using python to ensure exact byte sequences
    python3 -c '
import os

os.makedirs("/home/user/legacy_docs/raw_assets", exist_ok=True)

files = [
    ("item_01.tmp", b"%PDF-1.4\n" + b"\x00" * 15 * 1024),
    ("data_02.bin", b"\x89PNG\r\n\x1a\n" + b"\x00" * 12 * 1024),
    ("img_03.dat", b"\xFF\xD8\xFF\xE0" + b"\x00" * 20 * 1024),
    ("item_04.tmp", b"%PDF-1.4\n" + b"\x00" * 4 * 1024),
    ("text_05.log", b"Hello World" + b"\x00" * 15 * 1024),
    ("pic_06.var", b"\x89PNG\r\n\x1a\n" + b"\x00" * 11 * 1024),
]

for name, content in files:
    with open(f"/home/user/legacy_docs/raw_assets/{name}", "wb") as f:
        f.write(content)
'

    chmod -R 777 /home/user
