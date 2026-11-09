#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        nginx \
        redis-server \
        curl \
        gawk \
        coreutils

    pip3 install pytest flask redis python-dotenv gunicorn requests

    mkdir -p /app/backend
    mkdir -p /app/nginx
    mkdir -p /app/data/artifacts/v1.0
    mkdir -p /app/data/artifacts/v2.0

    cat << 'EOF' > /app/backend/app.py
from flask import Flask, jsonify, send_from_directory
import os
import redis
from dotenv import load_dotenv

load_dotenv()
app = Flask(__name__)
r = redis.Redis.from_url(os.getenv("REDIS_URL", "redis://127.0.0.1:6379/0"))

@app.route("/health")
def health():
    try:
        r.ping()
        return jsonify({"status": "ok"})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route("/artifacts/<version>/<filename>")
def artifact(version, filename):
    return send_from_directory(f"/app/data/artifacts/{version}", filename)

if __name__ == "__main__":
    app.run(port=5000)
EOF

    cat << 'EOF' > /app/nginx/nginx.conf
pid /tmp/nginx.pid;
events {}
http {
    access_log /tmp/access.log;
    error_log /tmp/error.log;
    client_body_temp_path /tmp/client_body;
    fastcgi_temp_path /tmp/fastcgi_temp;
    proxy_temp_path /tmp/proxy_temp;
    scgi_temp_path /tmp/scgi_temp;
    uwsgi_temp_path /tmp/uwsgi_temp;
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:5001;
        }
    }
}
EOF

    cat << 'EOF' > /app/backend/.env
REDIS_URL=unix:///tmp/redis.sock
EOF

    cat << 'EOF' > /app/start.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /app/nginx/nginx.conf
cd /app/backend
gunicorn -w 4 -b 127.0.0.1:5000 app:app --daemon
EOF
    chmod +x /app/start.sh

    # Create dummy artifacts (4 unique, 6 duplicates = 10 files of 50MB each)
    dd if=/dev/urandom of=/app/data/artifacts/v1.0/libfoo1.so bs=1M count=50
    dd if=/dev/urandom of=/app/data/artifacts/v1.0/libfoo2.so bs=1M count=50
    dd if=/dev/urandom of=/app/data/artifacts/v1.0/libfoo3.so bs=1M count=50
    dd if=/dev/urandom of=/app/data/artifacts/v1.0/libfoo4.so bs=1M count=50

    cp /app/data/artifacts/v1.0/libfoo1.so /app/data/artifacts/v1.0/libfoo1_dup.so
    cp /app/data/artifacts/v1.0/libfoo2.so /app/data/artifacts/v1.0/libfoo2_dup.so
    cp /app/data/artifacts/v1.0/libfoo3.so /app/data/artifacts/v2.0/libfoo3.so
    cp /app/data/artifacts/v1.0/libfoo4.so /app/data/artifacts/v2.0/libfoo4.so
    cp /app/data/artifacts/v1.0/libfoo1.so /app/data/artifacts/v2.0/libfoo1.so
    cp /app/data/artifacts/v1.0/libfoo2.so /app/data/artifacts/v2.0/libfoo2.so

    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
