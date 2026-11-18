#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server bubblewrap openssl curl gawk
    pip3 install pytest flask redis cryptography pyOpenSSL requests

    mkdir -p /app/services/nginx/certs
    mkdir -p /app/services/flask
    mkdir -p /app/services/redis
    mkdir -p /app/verifier

    # Generate initial weak cert
    openssl req -x509 -nodes -days 30 -newkey rsa:2048 \
        -keyout /app/services/nginx/certs/server.key \
        -out /app/services/nginx/certs/server.crt \
        -subj "/CN=localhost"

    cat << 'EOF' > /app/services/nginx/nginx.conf
worker_processes 1;
daemon off;
events {
    worker_connections 1024;
}
http {
    server {
        listen 8443 ssl;
        server_name localhost;

        ssl_certificate /app/services/nginx/certs/server.crt;
        ssl_certificate_key /app/services/nginx/certs/server.key;

        ssl_protocols TLSv1 TLSv1.1 TLSv1.2;

        location /api {
            proxy_pass http://127.0.0.1:5000;
        }
    }
}
EOF

    cat << 'EOF' > /app/services/flask/app.py
from flask import Flask, jsonify
import redis
import os

app = Flask(__name__)

redis_host = '127.0.0.1'
redis_port = 6379
redis_password = os.getenv('REDIS_PASSWORD', 'old_secret_pass')

@app.route('/api/status')
def status():
    try:
        r = redis.Redis(host=redis_host, port=redis_port, password=redis_password, decode_responses=True)
        r.ping()
        return jsonify({"status": "ok", "message": "Connected to Redis"})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    cat << 'EOF' > /app/services/redis/redis.conf
port 6379
requirepass old_secret_pass
daemonize no
EOF

    cat << 'EOF' > /app/services/start.sh
#!/bin/bash
redis-server /app/services/redis/redis.conf &
nginx -c /app/services/nginx/nginx.conf &
export REDIS_PASSWORD="old_secret_pass"
python3 /app/services/flask/app.py &
wait
EOF
    chmod +x /app/services/start.sh

    cat << 'EOF' > /app/verifier/score.py
import sys
print("Score: 100")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
