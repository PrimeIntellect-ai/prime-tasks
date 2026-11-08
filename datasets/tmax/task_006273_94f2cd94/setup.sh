#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import json
import hashlib
import configparser

# Directories
base_dir = "/home/user"
raw_docs_dir = os.path.join(base_dir, "raw_docs")
os.makedirs(os.path.join(raw_docs_dir, "folder_A"), exist_ok=True)
os.makedirs(os.path.join(raw_docs_dir, "folder_B", "nested"), exist_ok=True)

# 1. Create doc_rules.ini
config = configparser.ConfigParser()
config['PDF'] = {'magic': '25504446', 'directory': 'pdfs', 'extension': 'pdf'}
config['PNG'] = {'magic': '89504E47', 'directory': 'images', 'extension': 'png'}
config['ZIP'] = {'magic': '504B0304', 'directory': 'archives', 'extension': 'zip'}

with open(os.path.join(base_dir, "doc_rules.ini"), 'w') as f:
    config.write(f)

# 2. Generate raw files with specific headers
file_definitions = [
    {
        "path": os.path.join(raw_docs_dir, "folder_A", "file_001"),
        "content": b'\x25\x50\x44\x46\x2D\x31\x2E\x34' + b' dummy pdf content',
        "title": "System_Architecture"
    },
    {
        "path": os.path.join(raw_docs_dir, "folder_A", "file_002"),
        "content": b'\x89\x50\x4E\x47\x0D\x0A\x1A\x0A' + b' dummy png content',
        "title": "Network_Diagram"
    },
    {
        "path": os.path.join(raw_docs_dir, "folder_B", "nested", "file_003"),
        "content": b'\x50\x4B\x03\x04\x14\x00\x00\x00' + b' dummy zip content',
        "title": "Code_Samples"
    },
    {
        "path": os.path.join(raw_docs_dir, "folder_B", "file_004"),
        "content": b'\x25\x50\x44\x46\x2D\x31\x2E\x34' + b' another pdf content',
        "title": "API_Reference"
    }
]

metadata = {}

for fd in file_definitions:
    with open(fd["path"], 'wb') as f:
        f.write(fd["content"])

    file_hash = hashlib.sha1(fd["content"]).hexdigest()
    metadata[file_hash] = {"title": fd["title"]}

# 3. Create metadata.json
with open(os.path.join(raw_docs_dir, "metadata.json"), 'w') as f:
    json.dump(metadata, f, indent=4)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
