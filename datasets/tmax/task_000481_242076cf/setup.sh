#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx g++ zip unzip tar
    pip3 install pytest

    mkdir -p /app/data
    cat << 'EOF' > /app/server.py
import http.server
import socketserver
import os

PORT = 8081
DIRECTORY = "/app/data"

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

with socketserver.TCPServer(("", PORT), Handler) as httpd:
    httpd.serve_forever()
EOF

    mkdir -p /app/data/elf_files
    echo -ne '\x7fELF\x02\x01\x01\x00' > /app/data/elf_files/dummy.elf

    python3 -c '
import struct
path = "elf_files/dummy.elf".encode("utf-16le")
with open("/app/data/journal.wal", "wb") as f:
    f.write(struct.pack("<I", len(path)) + path)
'
    cd /app/data
    tar -czf archive.tar.gz elf_files journal.wal
    zip bundle.zip archive.tar.gz
    rm -rf archive.tar.gz elf_files journal.wal

    python3 -c '
import struct
path = "elf_files/dummy.elf".encode("utf-16le")
record = struct.pack("<I", len(path)) + path
with open("/app/large_journal.wal", "wb") as f:
    f.write(record * 1000)
'

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /artifacts/ {
            return 404;
        }
    }
}
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
