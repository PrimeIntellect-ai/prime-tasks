#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import struct

os.makedirs('/home/user', exist_ok=True)

config_content = """max_chunk_size=100
output_dir=/home/user/chunks
"""
with open('/home/user/chunk_config.ini', 'w') as f:
    f.write(config_content)

records = [
    "Project initialization started.\n",
    "Loading module A...\n",
    "Loading module B...\n",
    "Warning: module C not found.\n",
    "Project load complete.\n",
    "Starting main loop.\n",
    "Error: timeout reached.\n",
    "Shutting down.\n"
]

with open('/home/user/project_dump.bin', 'wb') as f:
    for rec in records:
        utf16_data = rec.encode('utf-16le')
        length = len(utf16_data)
        f.write(struct.pack('<I', length))
        f.write(utf16_data)
EOF

    python3 /tmp/setup.py
    chmod -R 777 /home/user
