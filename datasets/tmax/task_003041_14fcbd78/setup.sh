#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/projects/archive_mount/data/backups/old/
    mkdir -p /home/user/projects/restored/

    cat << 'EOF' > /home/user/setup_archive.py
import hashlib

def create_entry(filename, content, corrupt_checksum=False):
    content_bytes = content.encode('utf-8')
    hex_content = content_bytes.hex()

    if corrupt_checksum:
        checksum = "00000000000000000000000000000000"
    else:
        checksum = hashlib.md5(content_bytes).hexdigest()

    return f"===FILENAME: {filename}===\n===CHECKSUM: {checksum}===\n{hex_content}\n===END_FILE===\n"

archive_content = ""
archive_content += create_entry("config.json", '{"host": "localhost", "port": 8080}')
archive_content += create_entry("app_data.csv", 'id,name\n1,alice\n2,bob', corrupt_checksum=True)
archive_content += create_entry("main.py", 'print("Hello World!")')
archive_content += create_entry("readme.txt", 'This is a test backup.', corrupt_checksum=True)

with open("/home/user/projects/archive_mount/data/backups/old/backup.arc", "w") as f:
    f.write(archive_content)
EOF

    python3 /home/user/setup_archive.py
    rm /home/user/setup_archive.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
