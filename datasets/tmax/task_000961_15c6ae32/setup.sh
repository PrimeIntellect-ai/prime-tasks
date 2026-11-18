#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        nginx \
        redis-server \
        g++ \
        libcurl4-openssl-dev \
        libssl-dev \
        curl

    pip3 install pytest flask redis

    mkdir -p /app/nginx
    mkdir -p /home/user

    # Create the Flask API
    cat << 'EOF' > /app/api.py
from flask import Flask, request, jsonify
import hashlib

app = Flask(__name__)

@app.route('/api/v1/auth', methods=['GET'])
def auth():
    h = hashlib.sha256(b"s3cr3t_p4ss").hexdigest()
    return jsonify({"hash": h})

@app.route('/api/v1/data', methods=['GET'])
def data():
    auth_header = request.headers.get('Authorization')
    if auth_header == "Bearer s3cr3t_p4ss":
        return jsonify({"flag": "FLAG{vulpix_scan_99}"})
    return jsonify({"error": "Unauthorized"}), 401

@app.route('/api/v1/status', methods=['GET'])
def status():
    return jsonify({"status": "ok"})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Create incomplete nginx config
    cat << 'EOF' > /app/nginx/nginx.conf
worker_processes 1;
pid /tmp/nginx.pid;
events { worker_connections 1024; }
http {
    access_log /tmp/access.log;
    error_log /tmp/error.log;
    server {
        listen 8080;
        # Agent needs to configure proxy_pass to http://127.0.0.1:5000
        location /api/ {

        }
    }
}
EOF

    # Create start script
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /app/nginx/nginx.conf
nohup python3 /app/api.py > /tmp/api.log 2>&1 &
echo "Services started."
EOF
    chmod +x /app/start_services.sh

    # Create dictionary
    cat << 'EOF' > /app/dict.txt
password
123456
admin
s3cr3t_p4ss
qwerty
letmein
EOF

    # Create verify script
    cat << 'EOF' > /app/verify.py
import json
import sys

def verify():
    try:
        with open('/home/user/scan_report.json', 'r') as f:
            data = json.load(f)

        expected_token = "s3cr3t_p4ss"
        expected_flag = "FLAG{vulpix_scan_99}"

        score = 0.0
        if data.get("token") == expected_token:
            score += 0.5
        if data.get("flag") == expected_flag:
            score += 0.5

        print(f"Score: {score}")
        if score >= 0.95:
            sys.exit(0)
        else:
            sys.exit(1)
    except Exception as e:
        print(f"Failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    verify()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
