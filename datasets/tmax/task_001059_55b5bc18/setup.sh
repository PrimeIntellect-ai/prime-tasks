#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

python3 -c '
import os

os.makedirs("/home/user/artifacts_raw", exist_ok=True)
os.chdir("/home/user/artifacts_raw")

files = {
    "fake_text.txt": b"\x7f\x45\x4c\x46\x01\x02\x03",
    "image.doc": b"\x89\x50\x4e\x47\x0d\x0a\x1a\x0a",
    "archive.tar": b"\x1f\x8b\x08\x00\x00\x00\x00\x00",
    "data.rar": b"\x50\x4b\x03\x04\x14\x00\x00\x00",
    "unknown.dat": b"\x00\x11\x22\x33\x44\x55",
}

for name, content in files.items():
    with open(name, "wb") as f:
        f.write(content)

os.link("fake_text.txt", "fake_text_link.txt")
os.link("image.doc", "image_link.doc")

os.symlink("archive.tar", "valid_symlink.link")
os.symlink("/does/not/exist", "broken_symlink.link")

os.symlink("loop2.link", "loop1.link")
os.symlink("loop1.link", "loop2.link")
'

chmod -R 777 /home/user
