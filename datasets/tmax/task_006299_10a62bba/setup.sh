#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import os

os.makedirs("/home/user/doc_dumps", exist_ok=True)

raw_text = """===DOC-START===
Author: Alice Smith
Date: 2023-01-01
Tags: public, api

This is the public API documentation.
It has multiple lines.
===DOC-END===
===DOC-START===
Author: Bob Jones
Date: 2023-01-02
Tags: internal, draft

This is secret internal documentation.
Do not publish!
===DOC-END===
===DOC-START===
Author: Charlie Brown
Date: 2023-01-03
Tags: PUBLIC, guide, setup

How to setup the project.

Step 1: Install.
Step 2: Run.
===DOC-END===
"""

rle_bytes = bytearray()
for char in raw_text:
    rle_bytes.append(1)
    rle_bytes.append(ord(char))

with open("/home/user/doc_dumps/archive.rle", "wb") as f:
    f.write(rle_bytes)
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

chmod -R 777 /home/user
