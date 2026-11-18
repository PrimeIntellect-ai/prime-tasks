#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    # Create the required files with exact byte sequences using Python
    python3 -c '
import os
dir_path = b"/home/user/legacy_archive"
os.makedirs(dir_path, exist_ok=True)
files = [
    b"caf\xe9.TXT",
    b"m\xfcnchen.DAT",
    b"r\xe9sum\xe9.DOC",
    b"normal_file.CSV"
]
for f in files:
    open(os.path.join(dir_path, f), "wb").close()
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
