#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import os
import struct

def create_entry(path, content):
    path_bytes = path.encode('ascii')
    content_bytes = content.encode('utf-8')
    path_len = len(path_bytes)
    content_len = len(content_bytes)

    # <H is uint16_t little endian, <I is uint32_t little endian
    return struct.pack('<H', path_len) + path_bytes + struct.pack('<I', content_len) + content_bytes

def setup():
    os.makedirs('/home/user', exist_ok=True)

    entries = []
    # Safe entries
    entries.append(create_entry("intro.md", "# Welcome to [COMPANY_NAME] Docs\nThis is the intro."))
    entries.append(create_entry("api/setup.md", "## API Setup\n[COMPANY_NAME] provides a REST API."))
    entries.append(create_entry("internal/notes.txt", "Random notes. No company name here."))

    # Malicious/Zip-slip entries
    entries.append(create_entry("../hacked_root.md", "# HACKED\nYou extracted outside the folder!"))
    entries.append(create_entry("api/../../etc_fake/passwd", "root:x:0:0:root:/root:/bin/bash"))
    entries.append(create_entry("nested/../../sneaky.md", "Sneaky file [COMPANY_NAME]"))

    archive_data = b'DOCP' + b''.join(entries)

    with open('/home/user/docpack.bin', 'wb') as f:
        f.write(archive_data)

if __name__ == '__main__':
    setup()
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

chmod -R 777 /home/user
