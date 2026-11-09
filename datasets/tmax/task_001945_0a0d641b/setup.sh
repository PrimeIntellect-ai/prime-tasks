#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/drafts/networking
    mkdir -p /home/user/drafts/api/v1
    mkdir -p /home/user/archive

    cat << 'EOF' > /home/user/archiver.conf
# Archiver configuration
LOG_LEVEL=INFO
DEST_DIR=/home/user/archive
IGNORE_EXT=.draft
EOF

    echo "# Networking Basics" > /home/user/drafts/networking/intro.md
    echo "# API v1 Endpoints" > /home/user/drafts/api/v1/endpoints.md
    echo "TODO: write summary" > /home/user/drafts/summary.md

    cat << 'EOF' > /home/user/compress.py
import sys
import zlib
import base64

def main():
    data = sys.stdin.read().encode('utf-8')
    compressed = zlib.compress(data)
    encoded = base64.b64encode(compressed).decode('utf-8')
    sys.stdout.write(encoded)

if __name__ == "__main__":
    main()
EOF

    chmod +x /home/user/compress.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
