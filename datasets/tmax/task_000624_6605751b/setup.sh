#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx openssl
    pip3 install pytest flask gunicorn requests

    mkdir -p /app/ca /app/nginx /app/api

    # Generate CA key and cert
    openssl req -x509 -newkey rsa:2048 -keyout /app/ca/ca.key -out /app/ca/ca.crt -days 3650 -nodes -subj "/CN=Organization CA"
    chmod 644 /app/ca/ca.key

    # Create start script
    cat << 'EOF' > /app/start.sh
#!/bin/bash
nginx -c /app/nginx/nginx.conf
cd /app/api && gunicorn --bind 127.0.0.1:5000 app:app --daemon
EOF
    chmod +x /app/start.sh

    # Create Nginx config
    cat << 'EOF' > /app/nginx/nginx.conf
events {}
http {
    server {
        listen 8443 ssl;
        ssl_certificate /app/ca/ca.crt;
        ssl_certificate_key /app/ca/ca.key;
        ssl_client_certificate /app/ca/ca.crt;
        ssl_verify_client on;

        location / {
            proxy_pass http://127.0.0.1:5000;
        }
    }
}
EOF

    # Create Flask app
    cat << 'EOF' > /app/api/app.py
from flask import Flask, request
import base64
import auth_logic

app = Flask(__name__)

@app.route('/escalate', methods=['POST'])
def escalate():
    payload_b64 = request.form.get('payload')
    if not payload_b64:
        return "No payload", 400
    try:
        raw_payload = base64.b64decode(payload_b64)
        with open("/tmp/last_payload.bin", "wb") as f:
            f.write(raw_payload)
        auth_logic.audit_and_load(raw_payload)
        return "Processed", 200
    except Exception as e:
        return str(e), 500
EOF

    # Create auth_logic.py
    cat << 'EOF' > /app/api/auth_logic.py
import pickle

def audit_and_load(data):
    # Simulated privilege auditing framework that unsafely deserializes
    return pickle.loads(data)
EOF

    # Compile and remove source
    python3 -m py_compile /app/api/auth_logic.py
    mv /app/api/__pycache__/auth_logic.cpython-*.pyc /app/api/auth_logic.pyc
    rm /app/api/auth_logic.py
    rm -rf /app/api/__pycache__

    # Setup user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
