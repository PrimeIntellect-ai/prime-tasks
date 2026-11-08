#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server gcc zlib1g-dev
    pip3 install pytest flask redis gunicorn pyinstaller

    mkdir -p /app/bin /app/api /home/user

    # Create gpak-ref python script
    cat << 'EOF' > /tmp/gpak_ref.py
#!/usr/bin/env python3
import sys, os, zlib, struct

def pack(out_path, in_dir):
    files = []
    for root, _, filenames in os.walk(in_dir):
        for f in filenames:
            full_path = os.path.join(root, f)
            rel_path = os.path.relpath(full_path, in_dir)
            files.append((rel_path, full_path))
    files.sort(key=lambda x: x[0])

    with open(out_path, 'wb') as out:
        out.write(b'GPAK')
        out.write(struct.pack('<I', len(files)))
        for rel_path, full_path in files:
            path_encoded = rel_path.encode('utf-8')
            out.write(struct.pack('<H', len(path_encoded)))
            out.write(path_encoded)
            with open(full_path, 'rb') as f:
                data = f.read()
            out.write(struct.pack('<I', len(data)))
            comp_data = zlib.compress(data, level=9)
            out.write(struct.pack('<I', len(comp_data)))
            out.write(comp_data)

def unpack(in_path, out_dir):
    with open(in_path, 'rb') as f:
        magic = f.read(4)
        if magic != b'GPAK': return
        count = struct.unpack('<I', f.read(4))[0]
        for _ in range(count):
            path_len = struct.unpack('<H', f.read(2))[0]
            path = f.read(path_len).decode('utf-8')
            uncomp_size = struct.unpack('<I', f.read(4))[0]
            comp_size = struct.unpack('<I', f.read(4))[0]
            comp_data = f.read(comp_size)
            data = zlib.decompress(comp_data)
            out_path = os.path.join(out_dir, path)
            os.makedirs(os.path.dirname(out_path), exist_ok=True)
            with open(out_path, 'wb') as out:
                out.write(data)

if len(sys.argv) > 3:
    if sys.argv[1] == 'pack':
        pack(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == 'unpack':
        unpack(sys.argv[2], sys.argv[3])
EOF

    # Compile it into a binary using pyinstaller to satisfy the "binary" requirement
    pyinstaller --onefile /tmp/gpak_ref.py --distpath /app/bin --name gpak-ref
    chmod +x /app/bin/gpak-ref

    # Create Flask app scaffold
    cat << 'EOF' > /app/api/app.py
import os
from flask import Flask, request
import redis

app = Flask(__name__)
# Intentional bug: wrong redis port
r = redis.Redis(host='127.0.0.1', port=6380)

@app.route('/api/upload', methods=['POST'])
def upload():
    # missing logic
    return "OK", 200

if __name__ == '__main__':
    app.run(port=5000)
EOF

    # Configure Nginx without the /api/ proxy block
    cat << 'EOF' > /etc/nginx/sites-available/default
server {
    listen 8080 default_server;
    listen [::]:8080 default_server;

    root /var/www/html;
    index index.html index.htm index.nginx-debian.html;

    server_name _;

    location / {
        try_files $uri $uri/ =404;
    }
}
EOF

    # Ensure services are started during the test phase
    # Note: Apptainer doesn't run systemd, so we start them manually in a script
    # that can be executed, or just start them now (they might not persist).
    # We will write a wrapper script that the testing framework might use, and also start them here.
    service redis-server start || true
    service nginx start || true

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
