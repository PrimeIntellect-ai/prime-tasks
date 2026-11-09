#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import struct
import os

# 1. Create config file
config_content = """[Settings]
output_dir = /home/user/extracted_docs
"""
with open("/home/user/doc_config.ini", "w") as f:
    f.write(config_content)

# 2. Define files to pack
files_to_pack = [
    {
        "path": "intro.md",
        "content": b"# Introduction to our system\n"
    },
    {
        "path": "assets/logo.png",
        "content": b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR"
    },
    {
        "path": "../../../etc/passwd_override.txt",
        "content": b"root:x:0:0:root:/root:/bin/bash\nfake:x:1:1::/fake:/bin/bash"
    }
]

# 3. Write binary .docpack file
with open("/home/user/docs_archive.docpack", "wb") as f:
    # Magic bytes
    f.write(b"DOCP")
    # File count
    f.write(struct.pack("<I", len(files_to_pack)))

    for item in files_to_pack:
        path_bytes = item["path"].encode("utf-8")
        path_len = len(path_bytes)
        content = item["content"]
        content_len = len(content)

        f.write(struct.pack("<H", path_len))
        f.write(path_bytes)
        f.write(struct.pack("<I", content_len))
        f.write(content)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
