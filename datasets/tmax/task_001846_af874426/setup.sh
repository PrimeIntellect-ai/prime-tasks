#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    mkdir -p /home/user/dataset/folder1
    mkdir -p /home/user/dataset/folder2/nested
    mkdir -p /home/user/processed
    mkdir -p /home/user/links

    python3 -c '
import os
files = {
    "/home/user/dataset/file_a.log": "Log entry 1: ERROR_CODE_99 found.",
    "/home/user/dataset/folder1/file_b.log": "No errors here. Just standard text.",
    "/home/user/dataset/folder2/nested/file_c.log": "Critical ERROR_CODE_99 and another ERROR_CODE_99!"
}
for path, text in files.items():
    with open(path, "wb") as f:
        f.write(text.encode("utf-16le"))
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
