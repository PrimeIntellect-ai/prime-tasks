#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server curl
    pip3 install pytest flask redis python-dotenv gunicorn

    mkdir -p /app/nginx /app/flask_service

    cat << 'EOF' > /app/nginx/nginx.conf
worker_processes 1;
events { worker_connections 1024; }
http {
    server {
        listen 8080;
        location /api/ {
            proxy_pass http://127.0.0.1:9999;
        }
    }
}
EOF

    cat << 'EOF' > /app/flask_service/app.py
from flask import Flask, jsonify
import redis
import os
from dotenv import load_dotenv

load_dotenv('/app/flask_service/config.env')

app = Flask(__name__)
r = redis.Redis(host=os.getenv('REDIS_HOST', 'localhost'), port=int(os.getenv('REDIS_PORT', 6379)))

@app.route('/api/health')
def health():
    try:
        r.ping()
        return jsonify({"status": "ok", "redis": "connected"})
    except:
        return jsonify({"status": "error", "redis": "disconnected"}), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    cat << 'EOF' > /app/flask_service/config.env
REDIS_HOST=10.0.0.1
REDIS_PORT=9999
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /app/nginx/nginx.conf
cd /app/flask_service
gunicorn -w 1 -b 127.0.0.1:5000 app:app --daemon
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /app/reference_archiver
#!/usr/bin/env python3
import os
import sys
import zlib
import struct

def main():
    if len(sys.argv) != 2:
        sys.exit(1)
    target = sys.argv[1]

    results = []

    def walk(current_dir, visited):
        real_dir = os.path.realpath(current_dir)
        if real_dir in visited:
            return
        visited.add(real_dir)

        try:
            entries = sorted(os.listdir(current_dir))
        except OSError:
            visited.remove(real_dir)
            return

        for entry in entries:
            path = os.path.join(current_dir, entry)
            if os.path.isdir(path):
                walk(path, visited)
            elif os.path.isfile(path):
                if path.endswith(('.conf', '.yaml')):
                    rel_path = os.path.relpath(path, target)
                    results.append((rel_path, path))

        visited.remove(real_dir)

    walk(target, set())
    results.sort(key=lambda x: x[0])

    sys.stdout.buffer.write(b'CFG_BKP\x00')
    for rel_path, full_path in results:
        with open(full_path, 'rb') as f:
            data = f.read()
        rel_bytes = rel_path.encode('utf-8')
        comp_data = zlib.compress(data)

        sys.stdout.buffer.write(struct.pack('<H', len(rel_bytes)))
        sys.stdout.buffer.write(rel_bytes)
        sys.stdout.buffer.write(struct.pack('<I', len(data)))
        sys.stdout.buffer.write(struct.pack('<I', len(comp_data)))
        sys.stdout.buffer.write(comp_data)

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/reference_archiver

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
