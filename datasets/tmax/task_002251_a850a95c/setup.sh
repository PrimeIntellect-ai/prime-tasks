#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server nginx cron
    pip3 install pytest flask redis

    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /home/user/nginx
    mkdir -p /home/user/deploy/v1
    mkdir -p /home/user/deploy/v2
    mkdir -p /home/user/corpora_sample
    mkdir -p /home/user/corpora_hidden/evil
    mkdir -p /home/user/corpora_hidden/clean

    # Create Nginx conf
    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
events { worker_connections 1024; }
http {
    server {
        listen 8080;
        server_name localhost;

        # Missing location /api/ block
    }
}
EOF

    # Create Flask v1 (broken)
    cat << 'EOF' > /home/user/deploy/v1/app.py
from flask import Flask
app = Flask(__name__)
@app.route('/api/health')
def health():
    return "Broken v1", 500
if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    cat << 'EOF' > /home/user/deploy/v1/start.sh
#!/bin/bash
python3 /home/user/deploy/v1/app.py &
EOF
    chmod +x /home/user/deploy/v1/start.sh

    # Create Flask v2 (functional)
    cat << 'EOF' > /home/user/deploy/v2/app.py
import os
from flask import Flask, jsonify
import redis

app = Flask(__name__)

@app.route('/api/health')
def health():
    redis_host = os.environ.get('REDIS_HOST')
    if not redis_host:
        return jsonify({"status": "error", "message": "REDIS_HOST not set"}), 500
    try:
        r = redis.Redis(host=redis_host, port=6379, db=0)
        r.ping()
        return jsonify({"status": "ok", "redis": "connected"})
    except redis.ConnectionError:
        return jsonify({"status": "error", "message": "Redis not connected"}), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    cat << 'EOF' > /home/user/deploy/v2/start.sh
#!/bin/bash
python3 /home/user/deploy/v2/app.py &
EOF
    chmod +x /home/user/deploy/v2/start.sh

    # Create symlink
    ln -s /home/user/deploy/v1 /home/user/deploy/current

    # Create sample corpora files
    echo "GET /api/health HTTP/1.1\nHost: localhost" > /home/user/corpora_sample/clean1.txt
    echo "GET /api/health?id=1' OR 1=1 HTTP/1.1\nHost: localhost" > /home/user/corpora_sample/evil1.txt

    echo "GET /api/health HTTP/1.1\nHost: localhost" > /home/user/corpora_hidden/clean/clean1.txt
    echo "GET /api/health?file=../../etc/passwd HTTP/1.1\nHost: localhost" > /home/user/corpora_hidden/evil/evil1.txt
    echo "GET /api/health?q=<script>alert(1)</script> HTTP/1.1\nHost: localhost" > /home/user/corpora_hidden/evil/evil2.txt
    echo "GET /api/health?id=1 UNION SELECT 1,2,3 HTTP/1.1\nHost: localhost" > /home/user/corpora_hidden/evil/evil3.txt

    chmod -R 777 /home/user
