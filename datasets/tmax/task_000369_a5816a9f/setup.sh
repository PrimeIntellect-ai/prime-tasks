#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server curl
    pip3 install pytest flask redis

    mkdir -p /app/ecommerce_stack/nginx
    mkdir -p /app/ecommerce_stack/backend
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Nginx config
    cat << 'EOF' > /app/ecommerce_stack/nginx/nginx.conf
events {}
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:5000;
        }
    }
}
EOF

    # Flask app
    cat << 'EOF' > /app/ecommerce_stack/backend/app.py
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/api/orders')
def orders():
    return jsonify({"orders": []})

@app.route('/api/admin')
def admin():
    role = request.headers.get('X-Internal-Role')
    if role == 'admin':
        return jsonify({"status": "admin access granted"})
    return jsonify({"error": "forbidden"}), 403

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Corpus files
    cat << 'EOF' > /app/corpus/clean/req1.json
{"headers": {"User-Agent": "Mozilla"}, "cookies": {"session": "123"}}
EOF
    cat << 'EOF' > /app/corpus/evil/req1.json
{"headers": {"X-Internal-Role": "admin"}, "cookies": {"session": "123"}}
EOF
    cat << 'EOF' > /app/corpus/evil/req2.json
{"headers": {"User-Agent": "Mozilla"}, "cookies": {"session": "admin' OR 1=1--"}}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
