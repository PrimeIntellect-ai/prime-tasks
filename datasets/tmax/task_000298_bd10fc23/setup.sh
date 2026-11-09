#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
import os

os.makedirs("/home/user/docs_raw/subdir", exist_ok=True)
os.makedirs("/home/user/docs_raw/other", exist_ok=True)

with open("/home/user/doc_config.ini", "w") as f:
    f.write("""[Settings]
theme = dark
author = TechWriter

[Paths]
source_dir = /home/user/docs_raw
image_dir = /home/user/organized_images
temp_dir = /tmp/docs
""")

png_header = b"\x89\x50\x4E\x47\x0D\x0A\x1A\x0A\x00\x00\x00\x0D\x49\x48\x44\x52"

with open("/home/user/docs_raw/diagram.dat", "wb") as f:
    f.write(png_header + b"dummy data\n")

with open("/home/user/docs_raw/subdir/screenshot.png", "wb") as f:
    f.write(png_header + b"dummy data 2\n")

with open("/home/user/docs_raw/other/logo", "wb") as f:
    f.write(png_header + b"dummy data 3\n")

with open("/home/user/docs_raw/fake_image.png", "wb") as f:
    f.write(b"This is just a text file, not an image.\n")

with open("/home/user/docs_raw/data.bin", "wb") as f:
    f.write(b"\x00\x01\x02\x03\x04\x05\x06\x07\n")
'

    chmod -R 777 /home/user
