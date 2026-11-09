#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl
    pip3 install pytest

    mkdir -p /home/user/docs/src
    mkdir -p /home/user/docs/out
    mkdir -p /app

    cat << 'EOF' > /app/watcher.py
import time, os, subprocess
src_dir = "/home/user/docs/src"
seen = set(os.listdir(src_dir))
while True:
    time.sleep(1)
    current = set(os.listdir(src_dir))
    if current != seen:
        seen = current
        subprocess.run(["bash", "/app/transformer.sh"])
EOF

    cat << 'EOF' > /app/transformer.sh
#!/bin/bash
# Broken script
cp /home/user/docs/src/* /home/user/docs/out/
EOF
    chmod +x /app/transformer.sh

    cat << 'EOF' > /app/server.py
import http.server
import socketserver
import os

PORT = 8080
DIRECTORY = "/home/user/docs/out"

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

with socketserver.TCPServer(("127.0.0.1", PORT), Handler) as httpd:
    httpd.serve_forever()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
