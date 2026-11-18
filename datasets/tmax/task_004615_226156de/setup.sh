#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl openssl jq
    pip3 install pytest flask

    mkdir -p /app/ca /app/nginx /app/bin /app/logs /app/hidden /app/flask

    # Generate internal CA
    openssl genrsa -out /app/ca/ca.key 2048
    openssl req -x509 -new -nodes -key /app/ca/ca.key -sha256 -days 3650 -out /app/ca/ca.crt -subj "/CN=InternalCA"

    # Create Nginx config
    cat << 'EOF' > /app/nginx/nginx.conf
events {}
http {
    server {
        listen 8443 ssl;
        server_name localhost;

        ssl_certificate /app/ca/ca.crt;
        ssl_certificate_key /app/ca/ca.key;

        location / {
            proxy_pass http://127.0.0.1:5000;
        }
    }
}
EOF

    # Create Flask app
    cat << 'EOF' > /app/flask/app.py
from flask import Flask, jsonify
app = Flask(__name__)

@app.route('/api/status')
def status():
    return jsonify({"status": "ok"})

if __name__ == '__main__':
    app.run(port=5000)
EOF

    # Create start script
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
python3 /app/flask/app.py &
nginx -c /app/nginx/nginx.conf -g "daemon off;" &
EOF
    chmod +x /app/start_services.sh

    # Create dummy binaries for SUID check
    touch /app/bin/normal1 /app/bin/normal2 /app/bin/suid1 /app/bin/suid2
    chmod 755 /app/bin/normal1 /app/bin/normal2
    chmod 4755 /app/bin/suid1 /app/bin/suid2

    echo "/app/bin/suid1" > /app/hidden/true_suid.txt
    echo "/app/bin/suid2" >> /app/hidden/true_suid.txt

    # Create security logs
    cat << 'EOF' > /app/create_logs.py
import json

logs = [
    {"timestamp": "2023-10-01T10:00:00Z", "ip_address": "192.168.1.10", "event_type": "login_failed", "username": "admin"},
    {"timestamp": "2023-10-01T10:00:10Z", "ip_address": "192.168.1.10", "event_type": "login_failed", "username": "admin"},
    {"timestamp": "2023-10-01T10:00:20Z", "ip_address": "192.168.1.10", "event_type": "login_failed", "username": "admin"},
    {"timestamp": "2023-10-01T10:00:30Z", "ip_address": "192.168.1.10", "event_type": "login_failed", "username": "admin"},
    {"timestamp": "2023-10-01T10:00:40Z", "ip_address": "192.168.1.10", "event_type": "login_failed", "username": "admin"},
    {"timestamp": "2023-10-01T10:00:50Z", "ip_address": "192.168.1.10", "event_type": "login_failed", "username": "admin"},
    {"timestamp": "2023-10-01T10:01:00Z", "ip_address": "10.0.0.5", "event_type": "login_failed", "username": "user"},
]

with open("/app/logs/security.log", "w") as f:
    for log in logs:
        f.write(json.dumps(log) + "\n")

with open("/app/hidden/true_ips.json", "w") as f:
    json.dump(["192.168.1.10"], f)
EOF
    python3 /app/create_logs.py
    rm /app/create_logs.py

    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
