#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    # Create the python script to generate the archive
    cat << 'EOF' > /tmp/setup_archive.py
import struct
import os

os.makedirs('/home/user', exist_ok=True)

files_to_pack = [
    ("intro.md", b"# Introduction\nWelcome to the documentation.\n"),
    ("diagram.png", b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR...fake_png_data..."),
    ("setup.md", b"## Setup\nRun `make install` to build.\n"),
    ("notes.txt", b"Just some random notes. Ignore me."),
    ("api.md", b"### API Reference\n- `get_data()`\n- `set_data()`\n")
]

archive_path = '/home/user/doc_archive.bin'

with open(archive_path, 'wb') as f:
    for filename, data in files_to_pack:
        # Encode filename to 16 bytes, null padded
        name_bytes = filename.encode('utf-8')
        name_padded = name_bytes.ljust(16, b'\x00')

        # Pack filename (16s) and size (I, little-endian)
        header = struct.pack('<16sI', name_padded, len(data))

        f.write(header)
        f.write(data)

os.chmod(archive_path, 0o644)
EOF

    python3 /tmp/setup_archive.py
    rm /tmp/setup_archive.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
